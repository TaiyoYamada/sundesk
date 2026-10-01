//
//  GraphProjection.swift
//  SundeskGraphRenderer
//
//  Created by 山田大陽 on 2026/09/30.
//

import simd

/// 描画に渡す定数（シェーダーの `Uniforms` と同じ並び）。
struct GraphUniforms {
    var view: simd_float4x4
    var center: SIMD4<Float>
    /// x, y = 大きさ（pt）, z = 1 pt の画素数, w = ズーム。
    var viewport: SIMD4<Float>
    /// x = 奥行き, y = 目までの距離, z = 時計（秒）, w = 再生の位置（止めているときは 2）。
    var camera: SIMD4<Float>
    /// x = ダーク, y = 雲の濃さ, z = 線の濃さ, w = 点の大きさの倍率。
    var style: SIMD4<Float>
    /// x = 描く線の数, y = 線を束ねる強さ, z = 雲の半径（ワールド）。
    var extra: SIMD4<Float>
    var background0: SIMD4<Float>
    var background1: SIMD4<Float>

    /// 時間を再生していないときの、再生の位置。
    static let timelineOff: Float = 2
}

/// 点ごとの動く状態（シェーダーの `NodeState` と同じ並び）。
struct NodeState: Equatable {
    /// xyz = 寄せる先、w = 寄せる割合。
    var lens = SIMD4<Float>.zero
    /// x = 濃さ、y = 強調（0 = なし、1 = 隣・一致・経路、2 = 選択）、z = ホバー、w = 選んでからの秒（選んでいなければ -1）。
    var anim = SIMD4<Float>(1, 0, 0, -1)
}

/// 点を画面に写した結果（シェーダーの `Projected` と同じ並び）。
struct ProjectedNode: Equatable {
    /// xy = 画面の中央からの位置（pt、上が正）、z = 遠近の倍率、w = 奥行き。
    var screen: SIMD4<Float>
    /// x = 濃さ、y = 半径（pt）、z = 生まれたての光、w = 現れた割合。
    var look: SIMD4<Float>
    /// xyz = 寄せた後の座標、w = 強調。
    var world: SIMD4<Float>

    static let zero = ProjectedNode(screen: .zero, look: .zero, world: .zero)
}

/// 点ごとの変わらない値（シェーダーの `info`）。x = 半径、y = 生まれた時（なければ -1）、z = まとまりの添字、w = 雲の重み。
typealias NodeInfo = SIMD4<Float>

/// 点を画面に写す計算の、CPU での実装。シェーダーの `projectNodes` と同じ結果になる。
///
/// ラベルの置き場所と、押した点を探すのに使う（GPU の結果を待たずに、同じフレームの値を使える）。
enum GraphProjection {
    /// フレームごとに同じ値（カメラ、点の大きさの倍率、再生の位置）。
    struct Context {
        let camera: GraphCamera
        let rotation: simd_float3x3
        let nodeScale: Float
        let cursor: Float

        init(camera: GraphCamera, nodeScale: Float, cursor: Float) {
            self.camera = camera
            rotation = camera.rotation
            self.nodeScale = nodeScale
            self.cursor = cursor
        }
    }

    static func project(position: SIMD4<Float>, info: NodeInfo, state: NodeState, context: Context) -> ProjectedNode {
        let base = position.xyz
        let point = base + (state.lens.xyz - base) * state.lens.w
        let projected = context.camera.project(point, rotation: context.rotation)
        let life = lifetime(birth: info.y, cursor: context.cursor)
        let fog = 1 + (min(max(projected.z * projected.z, 0.2), 1) - 1) * context.camera.perspective
        let grow = 1 + 0.25 * state.anim.z + 0.6 * life.y
        let radius = info.x * context.nodeScale * projected.z * grow * (0.2 + 0.8 * life.x)
        return ProjectedNode(
            screen: projected, look: SIMD4(state.anim.x * life.x * fog, radius, life.y, life.x),
            world: SIMD4(point, state.anim.y))
    }

    /// 時間の再生: x = 現れた割合、y = 生まれたての光。
    static func lifetime(birth: Float, cursor: Float) -> SIMD2<Float> {
        guard cursor <= 1.5, birth >= 0 else { return [1, 0] }
        let age = cursor - birth
        return SIMD2(smoothstep(0, 0.015, age), age >= 0 ? exp(-age * 40) : 0)
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let ratio = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return ratio * ratio * (3 - 2 * ratio)
    }
}
