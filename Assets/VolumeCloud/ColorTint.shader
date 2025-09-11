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

            //屏幕纹理和深度图:
            TEXTURE2D_SAMPLER2D(_MainTex,sampler_MainTex);
            TEXTURE2D_SAMPLER2D(_CameraDepthTexture,sampler_CameraDepthTexture);//同时声明屏幕空间深度图纹理和采样器
            //3D纹理：
            TEXTURE3D_SAMPLER3D(_noise3D,sampler_noise3D);//同时声明3D纹理及其采样器
            float _noiseTexScale;//3D纹理尺寸
            
            float4 _Color;
            float _BlendMultiply;
            
            //世界空间坐标重建
            float4x4 _InverseProjectionMatrix;//投影矩阵逆矩阵（投影空间-》摄像机空间）
            float4x4 _InverseViewMatrix;//视图矩阵逆矩阵（摄像机空间-》世界空间）

            //云盒参数
            float3 _boundsMin;
            float3 _boundsMax;

            //步进参数
            float _step;
            float _rayStep;

            //大气散射参数
            float4 _colA;
            float4 _colB;
            float _colorOffset1;
            float _colorOffset2;
            float3 _WorldSpaceLightPos0;//主光源方向
            float3 _LightColor0;//主光源颜色
            float _lightAbsorptionTowardSun;//云粒子朝向太阳的吸光系数
            float _lightAbsorptionThroughCloud;//光穿过云层的吸收系数
            
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

            float SampleDensity(float3 rayPos)
            {
                //采样3D纹理
                float3 uvw = rayPos * _noiseTexScale;
                float4 shapeNoise = SAMPLE_TEXTURE3D(_noise3D,sampler_noise3D,uvw);
                shapeNoise = smoothstep(0.2,0.8,shapeNoise);//调整阈值
                return shapeNoise.r;
            }

                            //边界框最小值        //边界框最大值        //射线起点          //射线方向的倒数 
            float2 RayBoxDis(float3 boundsMin,float3 boundsMax,float3 rayStartPos,float3 invRayDir)
            {
                float3 t0 = (boundsMin - rayStartPos) * invRayDir;
                float3 t1 = (boundsMax - rayStartPos) * invRayDir;
                float3 tmin = min(t0,t1);
                float3 tmax = max(t0,t1);

                float disA = max(max(tmin.x, tmin.y), tmin.z); //最近进入点
                float disB = min(tmax.x, min(tmax.y, tmax.z)); //最近离开点

                float disToBox = max(0,disA);//相机到边界框的距离
                float disInsideBox = max(0,disB - disToBox);//光线在边界框内的距离
                return float2(disToBox,disInsideBox);
                
            }

            //对光线进行步进累计光照强度：
            float3 LightMarch(float3 position,float travelledDis)
            {
                float3 dirToLight = _WorldSpaceLightPos0.xyz;
                float disInsideBox = RayBoxDis(_boundsMin,_boundsMax,position,1/dirToLight).y;//获取从当前点位出发，沿灯光方向与云盒边界求交
                float stepSize = disInsideBox/10;//根据总距离计算沿光线步进的步长
                float totalDensity = 0;
                for (int step = 0; step < 8; ++step)//沿着灯光的步进次数
                {
                    position += dirToLight * stepSize;//向着灯光步进
                    totalDensity = max(0,SampleDensity(position) * stepSize);
                }
                float transmittance = exp(-totalDensity * _lightAbsorptionTowardSun);//透射率

                //将高亮部分和暗部映射为3段颜色，亮->灯光颜色、中->ColorA、暗->ColorB
                float3 cloudColor = lerp(_colA,_LightColor0,saturate(transmittance * _colorOffset1));
            }
            
            float4 Frag (VaryingsDefault i) : SV_Target
            {
                float4 screenBaseCol = SAMPLE_TEXTURE2D(_MainTex,sampler_MainTex,i.texcoord);//采样屏幕纹理
                float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture,sampler_CameraDepthTexture,i.texcoordStereo);//采样屏幕空间深度，texcoordStereo 本质上就是 屏幕空间坐标 (0~1 的 UV)
                float4 worldPos = GetWorldSpacePosition(depth,i.texcoord);//计算屏幕空间每个片元对应的世界空间坐标
                float3 rayStartPos = _WorldSpaceCameraPos;//世界空间相机位置（射线起始位置）
                float3 worldViewDir = normalize(worldPos.xyz - rayStartPos.xyz);// 射线起始位置 到 屏幕空间每个片元对应的世界坐标 的方向向量
                
                float depthEyeLinear = length(worldPos.xyz - _WorldSpaceCameraPos);//片元的世界空间位置到摄像机 的 距离
                float2 rayToContainerInfo = RayBoxDis(_boundsMin,_boundsMax,rayStartPos,1/worldViewDir);//得到是从相机发出的射线（方向指向片元），与 AABB 容器的交点信息
                float disToBox = rayToContainerInfo.x;//相机到容器的距离
                float disInsideBox = rayToContainerInfo.y;//相机发出的射线在容器中前进的距离
                float disLimit = min(depthEyeLinear - disToBox,disInsideBox);//相机到物体的距离 - 相机到容器的距离，这里与 光线在容器中前进的距离 取最小，过滤掉一些无效值
                /*
                 *disLimit是相机到物体（此处的物体是一个片元）的距离 减去 相机到容器的距离
                 * 如果disLimit>0,物体在容器内，需要进行步进
                 * disLimit<0,物体在容器外，停止步进
                 * 为什么要取最小：因为如果在某条射线上，片元可能在容器后方，此时 片元到相机的距离 减去 相机到包围盒的距离 大于 射线在包围盒里行进的距离。此时射线需要步进的距离就是 射线在包围盒里的行进距离
                 */
                
                //每个片元对应的密度
                //float cloudDensity = CloudRayMarching(rayStartPos,worldViewDir);
                //float cloudDensity = SampleDensity(disLimit,0.1,rayStartPos);

                float3 entryPoint = rayStartPos + worldViewDir * disToBox;//射线进入云盒的点位
                
                //根据disLimit步进
                float sumDensity = 0;//累计的密度值
                float _travelledDis = 0;//光线在云盒内步进的距离
                float stepSize = _step;//步长
                stepSize = exp(_step) * _rayStep;//???
                for (int j = 0;j < 32;j++)
                {
                    if (disLimit > _travelledDis)
                    {
                        rayStartPos = entryPoint + (worldViewDir * _travelledDis * _rayStep);//每步进一次修改一次起始点位
                        sumDensity += pow(SampleDensity(rayStartPos),5);//每步进一次采样一次3D纹理
                    }
                    _travelledDis += stepSize;
                }
                float cloudDensity = sumDensity;    
                
                //每个片元的密度 乘以 此处的纹理采样值（绘制云盒之前） 乘以 自定义的颜色值 + 绘制云盒之前的屏幕纹理采样值
                float4 finalCol = saturate(cloudDensity * screenBaseCol * _Color + screenBaseCol);
                
                return finalCol;
            }
            ENDHLSL
        }
    }
}
