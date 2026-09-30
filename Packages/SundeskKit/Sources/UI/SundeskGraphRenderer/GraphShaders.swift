//
//  GraphShaders.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/29.
//

/// Metal のシェーダー。`swift build` でも Xcode でも同じように動くよう、実行時にソースからコンパイルする。
///
/// 1 フレームの流れ:
/// 1. `projectNodes`（コンピュート）で、点ごとに画面の位置と大きさと濃さを 1 回だけ計算する
/// 2. 線、点、雲、ラベルは、その結果を読んで描く（同じ計算を頂点ごとに繰り返さない）
/// 3. `layoutStep`（コンピュート）で、次のフレームの配置を進める
enum GraphShaders {
    static var source: String { common + layout + projection + drawing + effects }

    static let common = """
        #include <metal_stdlib>
        using namespace metal;

        struct Uniforms {
            float4x4 view;       // 回転（3 次元で見るとき）
            float4 center;       // 画面の中央に来る座標（xyz）
            float4 viewport;     // x, y = 大きさ（pt）, z = 1 pt の画素数, w = ズーム（1 単位あたりの pt）
            float4 camera;       // x = 奥行き（0 = 平面, 1 = 透視）, y = 目までの距離, z = 時計（秒）, w = 再生の位置
            float4 style;        // x = ダーク, y = 雲の濃さ, z = 線の濃さ, w = 点の大きさの倍率
            float4 extra;        // x = 描く線の数, y = 線を束ねる強さ, z = 雲の半径（ワールド）, w = 未使用
            float4 background0;  // 背景の中央の色
            float4 background1;  // 背景の端の色
        };

        // 点ごとの動く状態（CPU がフレームごとに書く）
        struct NodeState {
            float4 lens;  // xyz = 寄せる先, w = 寄せる割合（選んだ点の隣）
            float4 anim;  // x = 濃さ, y = 強調（0 = なし, 1 = 隣・一致・経路, 2 = 選択）, z = ホバー, w = 選んでからの秒
        };

        // 点ごとの、画面に写した結果
        struct Projected {
            float4 screen;  // xy = 画面の中央からの位置（pt、上が正）, z = 遠近の倍率, w = 奥行き
            float4 look;    // x = 濃さ, y = 半径（pt）, z = 生まれたての光, w = 現れた割合
            float4 world;   // xyz = 寄せた後の座標, w = 強調
        };

        // 平面なら平行投影、3 次元なら透視投影。CPU の `GraphCamera.project` と同じ計算。
        static float4 projectPoint(float3 p, constant Uniforms &u) {
            float3 v = (u.view * float4(p - u.center.xyz, 0.0)).xyz;
            float eye = u.camera.y;
            float scale = mix(1.0, eye / max(eye - v.z, eye * 0.05), u.camera.x);
            return float4(v.xy * (u.viewport.w * scale), scale, v.z);
        }

        // 時間の再生: x = 現れた割合, y = 生まれたての光
        static float2 lifetime(float birth, float cursor) {
            if (cursor > 1.5 || birth < 0.0) return float2(1.0, 0.0);
            float age = cursor - birth;
            return float2(smoothstep(0.0, 0.015, age), age >= 0.0 ? exp(-age * 40.0) : 0.0);
        }

        struct FullscreenOut {
            float4 position [[position]];
            float2 uv;
        };

        // 画面全体を覆う 1 枚の三角形
        vertex FullscreenOut fullscreenVertex(uint vid [[vertex_id]]) {
            float2 corner = float2((vid << 1) & 2, vid & 2);
            FullscreenOut out;
            out.position = float4(corner * 2.0 - 1.0, 0.0, 1.0);
            out.uv = float2(corner.x, 1.0 - corner.y);
            return out;
        }

        """

    static let layout = """
        // MARK: - レイアウト（Fruchterman-Reingold の力学モデル、3 次元）

        struct LayoutParams {
            uint nodeCount;
            float repulsion;   // 反発の強さ（理想の距離の 2 乗）
            float attraction;  // 引力の強さ（理想の距離の逆数）
            float gravity;     // 中心へ引く強さ
            float damping;     // 速度の減衰
            float maxStep;     // 1 回に動ける距離の上限
            float alpha;       // 温度（だんだん下げて落ち着かせる）
            float cutoff2;     // これより遠い点からは反発を受けない（距離の 2 乗）
            float flatten;     // 奥行きをつぶす割合（平面に戻すとき）
            float cohesion;    // 同じまとまりの中心へ引く強さ
        };

        kernel void layoutStep(device const float4 *positions [[buffer(0)]],
                               device float4 *velocities [[buffer(1)]],
                               device float4 *nextPositions [[buffer(2)]],
                               device const uint *offsets [[buffer(3)]],
                               device const uint *neighbors [[buffer(4)]],
                               device const float *weights [[buffer(5)]],
                               device const uchar *pinned [[buffer(6)]],
                               constant LayoutParams &params [[buffer(7)]],
                               device const uint *groups [[buffer(8)]],
                               device const float4 *centroids [[buffer(9)]],
                               uint id [[thread_position_in_grid]]) {
            if (id >= params.nodeCount) return;
            float3 p = positions[id].xyz;
            float3 force = float3(0.0);
            for (uint j = 0; j < params.nodeCount; j++) {
                if (j == id) continue;
                float3 d = p - positions[j].xyz;
                float distance2 = max(dot(d, d), 0.01);
                if (distance2 > params.cutoff2) continue;
                force += d * (params.repulsion / distance2);
            }
            for (uint e = offsets[id]; e < offsets[id + 1]; e++) {
                float3 d = positions[neighbors[e]].xyz - p;
                force += d * (length(d) * params.attraction * weights[e]);
            }
            force -= p * params.gravity;
            uint group = groups[id];
            if (group != 0xFFFFFFFFu) force += (centroids[group].xyz - p) * params.cohesion;
            if (params.flatten > 0.0) force.z = 0.0;  // 平面に戻すあいだは、奥行きの方向に押さない
            float3 v = (velocities[id].xyz + force * params.alpha) * params.damping;
            float speed = length(v);
            if (speed > params.maxStep) v *= params.maxStep / speed;
            v.z *= 1.0 - params.flatten;
            if (pinned[id] != 0) v = float3(0.0);
            velocities[id] = float4(v, 0.0);
            float3 moved = p + v;
            moved.z *= 1.0 - params.flatten;
            nextPositions[id] = float4(moved, 0.0);
        }

        """

    static let projection = """
        // MARK: - 画面に写す

        kernel void projectNodes(device const float4 *positions [[buffer(0)]],
                                 device const float4 *info [[buffer(1)]],
                                 device const NodeState *states [[buffer(2)]],
                                 device Projected *out [[buffer(3)]],
                                 constant Uniforms &u [[buffer(4)]],
                                 constant uint &count [[buffer(5)]],
                                 uint id [[thread_position_in_grid]]) {
            if (id >= count) return;
            NodeState s = states[id];
            float3 p = mix(positions[id].xyz, s.lens.xyz, s.lens.w);
            float4 projected = projectPoint(p, u);
            float2 life = lifetime(info[id].y, u.camera.w);
            float fog = mix(1.0, clamp(projected.z * projected.z, 0.2, 1.0), u.camera.x);
            float grow = 1.0 + 0.25 * s.anim.z + 0.6 * life.y;
            float radius = info[id].x * u.style.w * projected.z * grow * mix(0.2, 1.0, life.x);
            out[id].screen = projected;
            out[id].look = float4(s.anim.x * life.x * fog, radius, life.y, life.x);
            out[id].world = float4(p, s.anim.y);
        }

        """
}
