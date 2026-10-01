//
//  GraphShaders+Effects.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

extension GraphShaders {
    /// 背景、まとまりの雲、文字。
    static let effects = """
        // MARK: - 雲（点ごとにぼかした円を足し合わせ、濃さの等高線でまとまりの形を描く）

        struct SplatOut {
            float4 position [[position]];
            float2 local;  // -1〜1
            float4 color;  // rgb = まとまりの色, a = 重み
        };

        vertex SplatOut splatVertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    device const Projected *nodes [[buffer(0)]],
                                    device const float4 *colors [[buffer(1)]],
                                    device const float4 *info [[buffer(2)]],
                                    constant Uniforms &u [[buffer(3)]]) {
            const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
            Projected p = nodes[iid];
            float weight = info[iid].w * p.look.w;
            float radius = min(u.extra.z * u.viewport.w * p.screen.z, 420.0);
            float2 halfSize = u.viewport.xy * 0.5;
            bool hidden = weight < 0.01 || any(abs(p.screen.xy) - radius > halfSize);
            SplatOut out;
            out.position = hidden ? float4(2.0, 2.0, 0.0, 1.0)
                                  : float4((p.screen.xy + corners[vid] * radius) / halfSize, 0.0, 1.0);
            out.local = corners[vid];
            out.color = float4(colors[iid].rgb, weight);
            return out;
        }

        fragment float4 splatFragment(SplatOut in [[stage_in]]) {
            float g = exp(-dot(in.local, in.local) * 4.0) * in.color.a * 0.4;
            return float4(in.color.rgb * g, g);
        }

        // 雲の濃さの画像から、まとまりの形（うすい塗りと等高線）を作る。乗算済みのアルファで返す
        static float4 cloud(texture2d<float> density, float2 uv, constant Uniforms &u) {
            constexpr sampler linear(filter::linear, address::clamp_to_edge);
            float4 d = density.sample(linear, uv);
            float amount = d.a;
            float3 color = d.rgb / max(amount, 1e-4);
            float width = fwidth(amount) * 1.2 + 1e-4;
            float contour = 1.0 - smoothstep(0.0, width, abs(amount - 0.55));
            float fill = smoothstep(0.3, 1.6, amount);
            float isDark = u.style.x;
            float strength = u.style.y;
            float fillAlpha = fill * (isDark > 0.5 ? 0.10 : 0.075) * strength;
            float lineAlpha = contour * (isDark > 0.5 ? 0.30 : 0.35) * strength;
            float3 lineColor = isDark > 0.5 ? mix(color, float3(1.0), 0.2) : color * 0.75;
            float4 result = float4(color * fillAlpha, fillAlpha);
            result = float4(lineColor * lineAlpha, lineAlpha) + result * (1.0 - lineAlpha);
            return float4(result.rgb, result.a * (isDark > 0.5 ? 0.3 : 1.0));
        }

        // MARK: - 背景（中央が少し明るい、ゆるやかなグラデーション）と雲を、1 回で塗る

        fragment float4 backgroundFragment(FullscreenOut in [[stage_in]],
                                           texture2d<float> density [[texture(0)]],
                                           constant Uniforms &u [[buffer(0)]]) {
            float2 p = in.uv - 0.5;
            p.x *= u.viewport.x / max(u.viewport.y, 1.0);
            float3 color = mix(u.background0.rgb, u.background1.rgb, smoothstep(0.05, 0.95, length(p)));
            // 帯が見えないように、ごくわずかに揺らす
            float noise = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453);
            color += (noise - 0.5) / 255.0;
            if (u.style.y > 0.01) {
                float4 layer = cloud(density, in.uv, u);
                color = layer.rgb + color * (1.0 - layer.a);
            }
            return float4(color, 1.0);
        }

        // MARK: - 文字（CoreText で描いた文字の地図から切り出す。周りに縁取りを付けて、線の上でも読めるようにする）

        struct LabelInstance {
            float4 rect;   // xy = 中心（画面の中央から、pt、上が正）, zw = 大きさ（pt）
            float4 uv;     // 文字の地図の中の場所（左上と右下）
            float4 color;  // 文字の色（rgb）と濃さ
            float4 halo;   // 縁取りの色（rgb）と濃さ
        };

        struct LabelOut {
            float4 position [[position]];
            float2 uv;
            float4 color;
            float4 halo;
        };

        vertex LabelOut labelVertex(uint vid [[vertex_id]],
                                    uint iid [[instance_id]],
                                    device const LabelInstance *labels [[buffer(0)]],
                                    constant Uniforms &u [[buffer(1)]]) {
            const float2 corners[4] = { float2(0, 0), float2(1, 0), float2(0, 1), float2(1, 1) };
            LabelInstance label = labels[iid];
            float2 corner = corners[vid];
            float2 point = label.rect.xy + (corner - 0.5) * label.rect.zw;
            LabelOut out;
            out.position = float4(point / (u.viewport.xy * 0.5), 0.0, 1.0);
            out.uv = float2(mix(label.uv.x, label.uv.z, corner.x), mix(label.uv.w, label.uv.y, corner.y));
            out.color = label.color;
            out.halo = label.halo;
            return out;
        }

        fragment float4 labelFragment(LabelOut in [[stage_in]],
                                      texture2d<float> atlas [[texture(0)]],
                                      constant Uniforms &u [[buffer(0)]]) {
            constexpr sampler linear(filter::linear, mip_filter::linear, address::clamp_to_edge);
            float coverage = atlas.sample(linear, in.uv).r;
            float2 texel = 3.0 / float2(atlas.get_width(), atlas.get_height());
            float halo = coverage;
            for (int k = 0; k < 12; k++) {
                float angle = float(k) * 0.5235988;
                halo = max(halo, atlas.sample(linear, in.uv + float2(cos(angle), sin(angle)) * texel).r);
            }
            float haloAlpha = smoothstep(0.0, 0.6, halo) * in.halo.a;
            float textAlpha = coverage * in.color.a;
            float4 result = float4(in.halo.rgb * haloAlpha, haloAlpha);
            return float4(in.color.rgb * textAlpha, textAlpha) + result * (1.0 - textAlpha);
        }

        """
}
