//
//  GraphShaders+Drawing.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

extension GraphShaders {
    /// 線と点。色は「乗算済みのアルファ」で返す。ダークでは光が足し算で重なるよう、アルファを小さくする。
    static let drawing = """
        // MARK: - 線（2 次のベジェ曲線。まとまりの間の線は、まとまりの中心へ寄せて束ねる）

        struct EdgeData {
            uint source;
            uint target;
            float weight;  // 0〜1
            float kind;    // 0 = ふつう, 1 = 選んだ点の隣, 2 = 経路（source から target へ光が流れる）
        };

        struct EdgeOut {
            float4 position [[position]];
            float4 color;
            float across;     // 線の中心からの距離（pt）
            float halfWidth;  // 線の太さの半分（pt）
            float t;          // 線の上の位置（0〜1）
            float kind;
        };

        constant uint kEdgeSegments = 12;

        static EdgeOut hiddenEdge() {
            EdgeOut out;
            out.position = float4(2.0, 2.0, 0.0, 1.0);
            out.color = float4(0.0);
            out.across = 0.0;
            out.halfWidth = 0.0;
            out.t = 0.0;
            out.kind = 0.0;
            return out;
        }

        vertex EdgeOut edgeVertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  device const EdgeData *edges [[buffer(0)]],
                                  device const Projected *nodes [[buffer(1)]],
                                  device const float4 *colors [[buffer(2)]],
                                  device const float4 *info [[buffer(3)]],
                                  device const float4 *centroids [[buffer(4)]],
                                  constant Uniforms &u [[buffer(5)]]) {
            EdgeData e = edges[iid];
            Projected a = nodes[e.source];
            Projected b = nodes[e.target];
            bool emphasized = e.kind > 0.5;
            float alpha = min(a.look.x, b.look.x);
            if (emphasized) {
                alpha = max(alpha, 0.0);
            } else {
                // 重い線から順に並んでいるので、描く数の終わりのほうは薄くして消す
                alpha *= 1.0 - smoothstep(u.extra.x * 0.6, u.extra.x, float(iid));
                alpha *= u.style.z * (0.35 + 0.65 * e.weight);
            }
            if (alpha < 0.002) return hiddenEdge();

            // 束ねる: まとまりの違う線は、2 つのまとまりの中心の中点へ曲げる
            float3 mid = (a.world.xyz + b.world.xyz) * 0.5;
            float3 control = mid;
            int ga = int(info[e.source].z);
            int gb = int(info[e.target].z);
            if (!emphasized && ga >= 0 && gb >= 0 && ga != gb) {
                float3 hub = (centroids[ga].xyz + centroids[gb].xyz) * 0.5;
                control = mix(mid, hub, u.extra.y);
            }
            float2 p0 = a.screen.xy;
            float2 p2 = b.screen.xy;
            float2 p1 = projectPoint(control, u).xy;

            // 見えない線は描かない
            float2 lo = min(min(p0, p1), p2);
            float2 hi = max(max(p0, p1), p2);
            float2 halfSize = u.viewport.xy * 0.5 + 8.0;
            if (any(hi < -halfSize) || any(lo > halfSize) || distance(p0, p2) < 0.5) return hiddenEdge();

            float t = float(vid / 2) / float(kEdgeSegments);
            float s = 1.0 - t;
            float2 point = s * s * p0 + 2.0 * s * t * p1 + t * t * p2;
            float2 tangent = 2.0 * s * (p1 - p0) + 2.0 * t * (p2 - p1);
            if (length(tangent) < 1e-4) tangent = p2 - p0;
            float2 normal = normalize(float2(-tangent.y, tangent.x));

            float width = e.kind > 1.5 ? 2.8 : (emphasized ? 1.6 : 0.6 + 0.9 * e.weight);
            width *= mix(1.0, mix(a.screen.z, b.screen.z, t), u.camera.x);
            float pixel = 1.0 / u.viewport.z;
            float halfWidth = max(width, pixel) * 0.5;
            float extent = halfWidth + pixel;
            float side = (vid % 2 == 0) ? -1.0 : 1.0;
            point += normal * side * extent;

            EdgeOut out;
            out.position = float4(point / (u.viewport.xy * 0.5), 0.0, 1.0);
            out.color = float4(mix(colors[e.source].rgb, colors[e.target].rgb, t), alpha * min(width / pixel, 1.0));
            out.across = side * extent;
            out.halfWidth = halfWidth;
            out.t = t;
            out.kind = e.kind;
            return out;
        }

        fragment float4 edgeFragment(EdgeOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
            float coverage = saturate((in.halfWidth - abs(in.across)) * u.viewport.z + 0.5);
            float alpha = in.color.a * coverage;
            float3 rgb = in.color.rgb;
            float isDark = u.style.x;
            if (in.kind > 1.5) {
                // 経路: 光の粒が流れる
                float wave = fract(in.t * 2.5 - u.camera.z * 0.9);
                float pulse = smoothstep(0.7, 0.97, wave) * (1.0 - smoothstep(0.97, 1.0, wave));
                rgb = mix(rgb, mix(float3(0.1), float3(1.0), isDark), pulse * 0.7);
                alpha = saturate(alpha * (0.8 + 0.9 * pulse));
            }
            float opacity = in.kind > 0.5 ? 1.0 : mix(1.0, 0.25, isDark);
            return float4(rgb * alpha, alpha * opacity);
        }

        // MARK: - 点（SDF の円。ダークでは光の暈、ライトでは白い縁と淡い影）

        struct NodeOut {
            float4 position [[position]];
            float2 local;   // 点の中心からの位置（pt）
            float radius;
            float4 color;
            float4 look;    // x = 濃さ, y = 強調, z = 生まれたての光, w = ホバー
            float ripple;   // 選んだときに広がる輪（0〜1、1 以上なら出さない）
        };

        vertex NodeOut nodeVertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  device const uint *order [[buffer(0)]],
                                  device const Projected *nodes [[buffer(1)]],
                                  device const float4 *colors [[buffer(2)]],
                                  device const NodeState *states [[buffer(3)]],
                                  constant Uniforms &u [[buffer(4)]]) {
            const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
            uint index = order[iid];
            Projected p = nodes[index];
            NodeState s = states[index];
            NodeOut out;
            float radius = p.look.y;
            float ripple = s.anim.w < 0.0 ? 2.0 : s.anim.w / 0.7;
            float extent = radius * 2.1 + 6.0 + 10.0 * p.look.z + (ripple < 1.0 ? 36.0 : 0.0);
            float2 halfSize = u.viewport.xy * 0.5;
            bool hidden = p.look.x < 0.004 || any(abs(p.screen.xy) - extent > halfSize);
            float2 corner = corners[vid] * extent;
            out.position = hidden ? float4(2.0, 2.0, 0.0, 1.0)
                                  : float4((p.screen.xy + corner) / halfSize, 0.0, 1.0);
            out.local = corner;
            out.radius = radius;
            out.color = colors[index];
            out.look = float4(p.look.x, s.anim.y, p.look.z, s.anim.z);
            out.ripple = ripple;
            return out;
        }

        // 乗算済みのアルファで、上に重ねる
        static float4 over(float4 top, float4 bottom) {
            return top + bottom * (1.0 - top.a);
        }

        fragment float4 nodeFragment(NodeOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
            float pixel = 1.0 / u.viewport.z;
            float d = length(in.local);
            float r = in.radius;
            float isDark = u.style.x;
            float emphasis = in.look.y;
            float3 base = in.color.rgb;

            // 光の暈（ダークは足し算、ライトは淡い色の影）
            float spread = r * 0.9 + 3.0 + 4.0 * in.look.z;
            float glow = exp(-pow(max(d - r * 0.6, 0.0) / spread, 2.0) * 1.6);
            float glowStrength = 0.16 + 0.22 * min(emphasis, 1.0) + 0.35 * step(1.5, emphasis) + 1.2 * in.look.z;
            float4 color = isDark > 0.5 ? float4(base * glow * glowStrength, 0.0)
                                        : float4(base * glow * glowStrength * 0.25, glow * glowStrength * 0.25);

            // 縁（ライトは白、ダークは背景の色）で、線と重なっても点が浮いて見えるように
            float rim = saturate((r + 1.3 - d) / pixel + 0.5);
            float3 rimColor = isDark > 0.5 ? u.background0.rgb : float3(1.0);
            color = over(float4(rimColor, 1.0) * rim * (isDark > 0.5 ? 0.6 : 0.95), color);

            // 円（上から光が当たったように、少しだけ明るさを変える）
            float fill = saturate((r - d) / pixel + 0.5);
            float2 n = in.local / max(r, 1e-3);
            float light = saturate(0.5 + 0.5 * dot(n, float2(-0.45, 0.55)));
            float3 core = mix(base * (isDark > 0.5 ? 0.9 : 0.92), mix(base, float3(1.0), 0.35), light * light);
            core = mix(core, float3(1.0), 0.5 * in.look.z);
            color = over(float4(core, 1.0) * fill, color);

            // 選んだ点の輪と、選んだ瞬間に広がる輪
            float3 ringColor = isDark > 0.5 ? float3(0.96, 0.97, 1.0) : float3(0.12, 0.13, 0.16);
            float selected = step(1.5, emphasis);
            float ring = saturate((0.9 - abs(d - (r + 3.5))) / pixel + 0.5) * max(selected, in.look.w * 0.6);
            color = over(float4(ringColor, 1.0) * ring, color);
            if (in.ripple < 1.0) {
                float radius = r + 4.0 + in.ripple * 32.0;
                float wave = saturate((1.2 - abs(d - radius)) / pixel + 0.5) * (1.0 - in.ripple) * 0.8;
                color = over(float4(base, 1.0) * wave, color);
            }
            return color * in.look.x;
        }

        """
}
