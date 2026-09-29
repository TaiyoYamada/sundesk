//
//  GraphShaders.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

/// Metal のシェーダー。`swift build` でも Xcode でも同じように動くよう、実行時にソースからコンパイルする。
enum GraphShaders {
    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        // MARK: - レイアウト（Fruchterman-Reingold の力学モデル）

        struct LayoutParams {
            uint nodeCount;
            float repulsion;   // 反発の強さ（理想の距離の 2 乗）
            float attraction;  // 引力の強さ（理想の距離の逆数）
            float gravity;     // 中心へ引く強さ
            float damping;     // 速度の減衰
            float maxStep;     // 1 回に動ける距離の上限
            float alpha;       // 温度（だんだん下げて落ち着かせる）
            float cutoff2;     // これより遠い点からは反発を受けない（距離の 2 乗）
        };

        kernel void layoutStep(device const float2 *positions [[buffer(0)]],
                               device float2 *velocities [[buffer(1)]],
                               device float2 *nextPositions [[buffer(2)]],
                               device const uint *offsets [[buffer(3)]],
                               device const uint *neighbors [[buffer(4)]],
                               device const float *weights [[buffer(5)]],
                               device const uchar *pinned [[buffer(6)]],
                               constant LayoutParams &params [[buffer(7)]],
                               uint id [[thread_position_in_grid]]) {
            if (id >= params.nodeCount) return;
            float2 p = positions[id];
            float2 force = float2(0.0);
            for (uint j = 0; j < params.nodeCount; j++) {
                if (j == id) continue;
                float2 d = p - positions[j];
                float distance2 = max(dot(d, d), 0.01);
                if (distance2 > params.cutoff2) continue;
                force += d * (params.repulsion / distance2);
            }
            for (uint e = offsets[id]; e < offsets[id + 1]; e++) {
                float2 d = positions[neighbors[e]] - p;
                force += d * (length(d) * params.attraction * weights[e]);
            }
            force -= p * params.gravity;
            float2 v = (velocities[id] + force * params.alpha) * params.damping;
            float speed = length(v);
            if (speed > params.maxStep) v *= params.maxStep / speed;
            if (pinned[id] != 0) v = float2(0.0);
            velocities[id] = v;
            nextPositions[id] = p + v;
        }

        // MARK: - 描画

        struct Uniforms {
            float2 viewportSize;  // ポイント
            float2 center;        // 画面の中央に来る座標
            float zoom;           // 1 単位あたりのポイント
            float nodeScale;
            int selected;
            float4 ringColor;
        };

        struct EdgeOut {
            float4 position [[position]];
            float4 color;
        };

        vertex EdgeOut edgeVertex(uint vid [[vertex_id]],
                                  device const float2 *positions [[buffer(0)]],
                                  device const uint2 *edges [[buffer(1)]],
                                  device const float4 *colors [[buffer(2)]],
                                  constant Uniforms &u [[buffer(3)]]) {
            uint2 edge = edges[vid / 2];
            uint node = (vid % 2 == 0) ? edge.x : edge.y;
            float2 screen = (positions[node] - u.center) * u.zoom;
            EdgeOut out;
            out.position = float4(screen / (u.viewportSize * 0.5), 0.0, 1.0);
            out.color = colors[vid / 2];
            return out;
        }

        fragment float4 edgeFragment(EdgeOut in [[stage_in]]) {
            return in.color;
        }

        struct NodeOut {
            float4 position [[position]];
            float2 local;
            float4 color;
            float radius;
            float selected;
        };

        vertex NodeOut nodeVertex(uint vid [[vertex_id]],
                                  uint iid [[instance_id]],
                                  device const float2 *positions [[buffer(0)]],
                                  device const float *radii [[buffer(1)]],
                                  device const float4 *colors [[buffer(2)]],
                                  constant Uniforms &u [[buffer(3)]]) {
            const float2 corners[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
            float radius = radii[iid] * u.nodeScale;
            float extent = radius + 4.0;
            float2 corner = corners[vid] * extent;
            float2 screen = (positions[iid] - u.center) * u.zoom + corner;
            NodeOut out;
            out.position = float4(screen / (u.viewportSize * 0.5), 0.0, 1.0);
            out.local = corner;
            out.color = colors[iid];
            out.radius = radius;
            out.selected = (int(iid) == u.selected) ? 1.0 : 0.0;
            return out;
        }

        fragment float4 nodeFragment(NodeOut in [[stage_in]], constant Uniforms &u [[buffer(0)]]) {
            float d = length(in.local);
            float fill = clamp(in.radius - d + 0.5, 0.0, 1.0);
            float4 color = float4(in.color.rgb, in.color.a * fill);
            if (in.selected > 0.5) {
                float ring = clamp(1.5 - abs(d - (in.radius + 2.0)), 0.0, 1.0);
                color = mix(color, u.ringColor, ring);
                color.a = max(color.a, ring);
            }
            if (color.a <= 0.0) discard_fragment();
            return color;
        }
        """
}
