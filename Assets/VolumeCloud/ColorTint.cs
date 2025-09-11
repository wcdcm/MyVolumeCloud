using System;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

[Serializable]
[PostProcess(typeof(ColorTintRenderer), PostProcessEvent.AfterStack, "Unity/ColorTint")]
public class ColorTint : PostProcessEffectSettings
{
    [Tooltip("ColorTint")] 
    public ColorParameter color = new ColorParameter { value = Color.white };

    [Range(0f, 1f), Tooltip("ColorTint intensity")]
    public FloatParameter blend = new FloatParameter { value = 0.5f };

    #region Texture
    
    [Tooltip("3D噪声纹理")]
    public TextureParameter noise3D = new TextureParameter { value = null };
    [Tooltip("3D噪声纹理尺寸")] [Range(0.01f, 0.02f)]
    public FloatParameter noiseTexScale = new FloatParameter { value = 0.01f };
    
    #endregion

    #region DensityCaculate
    [Tooltip("光线步进步长")][Range(0.1f, 3f)]
    public FloatParameter step = new FloatParameter { value = 2f };//光线步进步长（影响渲染精度和性能）
    [Tooltip("次级光线步长")][Range(0.1f, 2f)]
    public FloatParameter rayStep = new FloatParameter { value = 1.2f };//次级光线步长（用于阴影或者二次散射）

    #endregion
    
    #region Light 用于云的散射渐变
    
    public ColorParameter colA = new ColorParameter { value = Color.white };//用于云的散射渐变 中
    public ColorParameter colB = new ColorParameter { value = Color.white };//用于云的散射渐变 暗
    public FloatParameter colorOffset1 = new FloatParameter { value = 0.59f };//控制颜色插值的偏移值，在Shader中通过线性插值决定云的色彩过渡。
    public FloatParameter colorOffset2 = new FloatParameter { value = 1.02f };//控制颜色插值的偏移值，在Shader中通过线性插值决定云的色彩过渡。
    
    /// <summary>
    /// 云粒子朝向太阳的吸光系数。
    /// </summary>
    public FloatParameter lightAbsorptionTowardSun = new FloatParameter { value = 0.1f };
    
    /// <summary>
    /// 光穿过云层的吸收系数（厚度越大，透光率越低）。
    /// </summary>
    public FloatParameter lightAbsorptionThroughCloud = new FloatParameter { value = 1 };
    
    /// <summary>
    /// : 控制相函数（Phase Function），模拟云中光散射的方向性（如向前散射）。
    /// </summary>
    public Vector4Parameter phaseParams = new Vector4Parameter { value = new Vector4(0.72f, 1, 0.5f, 1.58f) };
    #endregion
}

public sealed class ColorTintRenderer : PostProcessEffectRenderer<ColorTint>
{
    private GameObject cloudBox;
    private Vector3 boundsMin;
    private Vector3 boundsMax;
    Transform cloudBoxTransform;

    public override void Init()
    {
        base.Init();
        cloudBox = GameObject.Find("CloudBox");
        if (cloudBox != null)
        {
            cloudBoxTransform = cloudBox.GetComponent<Transform>();//获取云盒的Transform组件
        }
    }

    public override void Render(PostProcessRenderContext context)
    {
        var cmd = context.command;
        cmd.BeginSample("ScreenColorTint");
        var sheet = context.propertySheets.Get(Shader.Find("Hidden/PostProcessing/ColorTint"));
        sheet.properties.SetColor(Shader.PropertyToID("_Color"), settings.color);
        sheet.properties.SetFloat(Shader.PropertyToID("_BlendMultiply"), settings.blend);

        //根据屏幕空间重建世界坐标,context.camera代表当前正在参与渲染的摄像机
        Matrix4x4 projectionMatrix = GL.GetGPUProjectionMatrix(context.camera.projectionMatrix, false);
        sheet.properties.SetMatrix(Shader.PropertyToID("_InverseProjectionMatrix"), projectionMatrix.inverse);
        sheet.properties.SetMatrix(Shader.PropertyToID("_InverseViewMatrix"), context.camera.cameraToWorldMatrix);

        //计算并传入云盒参数
        if (cloudBoxTransform != null)
        {
            boundsMin = cloudBoxTransform.position - cloudBoxTransform.localScale/2;
            boundsMax = cloudBoxTransform.position + cloudBoxTransform.localScale/2;
            sheet.properties.SetVector(Shader.PropertyToID("_boundsMin"), boundsMin);
            sheet.properties.SetVector(Shader.PropertyToID("_boundsMax"), boundsMax);
        }
        
        //传入3D纹理
        if (settings.noise3D.value != null)
        {
            sheet.properties.SetTexture(Shader.PropertyToID("_noise3D"), settings.noise3D.value);
        }

        if (settings.noiseTexScale.value != 0)
        {
            sheet.properties.SetFloat(Shader.PropertyToID("_noiseTexScale"), settings.noiseTexScale.value);
        }
        
        //传入步进参数
        if (settings.step.value != 0)
        {
            sheet.properties.SetFloat(Shader.PropertyToID("_step"), settings.step.value);
        }

        if (settings.rayStep.value != 0)
        {
            sheet.properties.SetFloat(Shader.PropertyToID("_rayStep"), settings.rayStep.value);
        }
        
        //传入大气散射计算参数
        sheet.properties.SetColor(Shader.PropertyToID("_colA"),settings.colA);
        sheet.properties.SetColor(Shader.PropertyToID("_colB"),settings.colB);
        sheet.properties.SetFloat(Shader.PropertyToID("_colorOffset1"), settings.colorOffset1.value);
        sheet.properties.SetFloat(Shader.PropertyToID("_colorOffset2"), settings.colorOffset2.value);
        sheet.properties.SetFloat(Shader.PropertyToID("_lightAbsorptionTowardSun"),settings.lightAbsorptionTowardSun.value);
        sheet.properties.SetFloat(Shader.PropertyToID("_lightAbsorptionThroughCloud"),settings.lightAbsorptionThroughCloud.value);
        var light = RenderSettings.sun;//获取主光源
        if (light != null)
        {
            var worldSpaceLightDir = -light.transform.forward;
            var lightColor = light.color;
            //设置主光源的全局变量
            Shader.SetGlobalVector(Shader.PropertyToID("_WorldSpaceLightPos0"), new Vector4(worldSpaceLightDir.x, worldSpaceLightDir.y, worldSpaceLightDir.z, 0));
            Shader.SetGlobalColor(Shader.PropertyToID("_LightColor0"), lightColor);
        }
        
        context.command.BlitFullscreenTriangle(context.source, context.destination, sheet, 0); //PostProcessing 会自动把 context.source 绑定到 Shader 的 _MainTex
        cmd.EndSample("ScreenColorTint");
    }
    /*
     *BlitFullscreenTriangle方法含义:
     * BlitFullscreenTriangle(source, destination, sheet, passIndex)
     * source → 输入纹理（通常是屏幕当前渲染结果 context.source）
     * destination → 输出纹理（最终渲染目标 context.destination）
     * sheet → PostProcess PropertySheet，封装 用来进行后处理的Shader 和参数
     * passIndex → Shader 的 Pass 索引，决定使用 Shader 的哪一段逻辑
     */
    /*
     * BlitFullscreenTriangle实际上做的事：
     * 在 GPU 上绘制 一个覆盖整个屏幕的三角形（Full-Screen Triangle），顶点坐标覆盖 NDC 空间 [-1,1]
     * 为什么用三角形而不是四边形？
     * 减少一个顶点，避免多余插值，性能更高
     * 对每个屏幕像素调用 Shader Pass 进行 片段着色器运算
     * SAMPLE_TEXTURE2D(_MainTex, ...) 读取输入屏幕纹理颜色
     * 进行各种后处理效果（这里 Pass 0 可能是体积云的 Ray Marching，或者调色、模糊等）
     * 结果写入 destination 渲染目标
     * 也就是最终屏幕或者下一个后处理 Pass 的输入
     */
}