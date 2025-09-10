Shader "Hidden/PostProcessing/ColorTint"
{
    SubShader
    {
        Cull Off ZWrite Off ZTest Always
        Pass
        {
            HLSLPROGRAM
            #pragma vertex VertDefault
            #pragma fragment Frag
            #include "Packages/com.unity.postprocessing/PostProcessing/Shaders/StdLib.hlsl"
            
            TEXTURE2D_SAMPLER2D(_MainTex,sampler_MainTex);
            TEXTURE2D_SAMPLER2D(_CameraDepthTexture,sampler_CameraDepthTexture);//声明屏幕空间深度图和采样器
            
            float4 _Color;
            float _BlendMultiply;
            float4x4 _InverseProjectionMatrix;//投影矩阵逆矩阵（投影空间-》摄像机空间）
            float4x4 _InverseViewMatrix;//视图矩阵逆矩阵（摄像机空间-》世界空间）

            float3 _boundsMin;
            float3 _boundsMax;
            
            
            float4 GetWorldSpacePosition(float depth,float2 uv)//传入屏幕空间深度和屏幕空间UV
            {
                float4 viewSpaceVector = mul(_InverseProjectionMatrix,float4(uv*2 - 1,depth,1));
                viewSpaceVector.xyz /= viewSpaceVector.w;
                float4 worldSpaceVector = mul(_InverseViewMatrix,float4(viewSpaceVector.xyz,1));
                return worldSpaceVector;
            }

            float CloudRayMarching(float3 startPoint,float3 direction)
            {
                float3 testPoint = startPoint;
                direction *= 0.5;//每次步进0.5m
                float sum = 0;
                for (int i = 0;i < 256;i++)
                {
                    testPoint += direction;
                    if (testPoint.x > -10&&testPoint.x < 10 &&
                        testPoint.y > -10&&testPoint.y < 10 &&
                        testPoint.z > 10&&testPoint.z < 30)
                    {
                        sum += 0.1;
                    }
                }
                return sum;
            }

            float SampleDensity(float disLimit,float rayStep)
            {
                float sumDensity = 0;
                float _disTravelled = 0;
                for (int j = 0; j < 32;j++)
                {
                    if (disLimit > _disTravelled)
                    {
                        sumDensity += 0.1;
                        // if (sumDensity > 1)
                        //     break;
                    }
                    _disTravelled += rayStep;
                }
                return sumDensity;
            }

                            //边界框最小值        //边界框最大值        //射线起点          //射线方向的倒数
            float2 RayBoxDis(float3 boundsMin,float3 boundsMax,float3 rayStartPos,float3 invRayDir)
            {
                float3 t0 = (boundsMin - rayStartPos) * invRayDir;
                float3 t1 = (boundsMax - rayStartPos) * invRayDir;
                float3 tmin = min(t0,t1);
                float3 tmax = max(t0,t1);

                float disA = max(max(tmin.x, tmin.y), tmin.z); //进入点
                float disB = min(tmax.x, min(tmax.y, tmax.z)); //离开点

                float disToBox = max(0,disA);//相机到边界框的距离
                float disInsideBox = max(0,disB - disToBox);//光线在边界框内的距离
                return float2(disToBox,disInsideBox);
                
            }
            
            float4 Frag (VaryingsDefault i) : SV_Target
            {
                //采样屏幕纹理
                float4 screenBaseCol = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.texcoord);
                //采样屏幕空间深度
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture,sampler_CameraDepthTexture,i.texcoordStereo);//texcoordStereo 本质上就是 屏幕空间坐标 (0~1 的 UV)
                //计算屏幕空间每个像素对应的世界空间坐标
                float4 worldPos = GetWorldSpacePosition(depth,i.texcoord);
                //世界空间相机位置（射线起始位置）
                float3 rayStartPos = _WorldSpaceCameraPos;
                // 射线起始位置 到 屏幕空间每个像素的世界坐标 的方向向量
                float3 worldViewDir = normalize(worldPos.xyz - rayStartPos.xyz);

                
                float depthEyeLinear = length(worldPos.xyz - _WorldSpaceCameraPos);//每个像素的世界空间位置到摄像机的距离
                float2 rayToContainerInfo = RayBoxDis(_boundsMin,_boundsMax,rayStartPos,1/worldViewDir);//得到射线到容器的信息
                float disToBox = rayToContainerInfo.x;//相机到容器的距离
                float disInsideBox = rayToContainerInfo.y;//射线穿过包围盒的距离
                float disLimit = min(depthEyeLinear - disToBox,disInsideBox);//相机到物体的距离 - 相机到容器的距离，这里与 光线是否在容器中 取最小，过滤掉一些无效值

                //每个像素对应的体积云的密度
                float cloudDensity = CloudRayMarching(rayStartPos,worldViewDir);
                cloudDensity = SampleDensity(disLimit,0.1);
                
                //screenBaseCol = lerp(screenBaseCol,screenBaseCol * _Color,_BlendMultiply);
                return saturate(cloudDensity * screenBaseCol * _Color + screenBaseCol);
            }
            ENDHLSL
        }
    }
}
