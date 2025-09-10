using System;
using UnityEngine;
using UnityEngine.Rendering.PostProcessing;

[Serializable]
[PostProcess(typeof(ColorTintRenderer), PostProcessEvent.AfterStack, "Unity/ColorTint")]
public class ColorTint : PostProcessEffectSettings
{
    [Tooltip("ColorTint")] public ColorParameter color = new ColorParameter { value = Color.white };

    [Range(0f, 1f), Tooltip("ColorTint intensity")]
    public FloatParameter blend = new FloatParameter { value = 0.5f };
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