import Foundation
import SwiftUI
import DesignSystem

/// 圧縮中インジケーターのドット絵サイドスクロール（マリオ型: 犬は画面左寄りに固定し、
/// 世界が右→左へ流れる）。1サイクルで小さな物語を演じ、サイクルごとにステージ
/// （海→川→砂漠→火山→氷山→宇宙）が切り替わる:
/// 走る（海では犬掻きで泳ぐ）→ 障害物をジャンプ → 出会い（戦闘/友達）→
/// ご褒美＝装備の獲得 → 次のステージへ。地形には上り坂・下り坂があり（火山は
/// 山登り→山頂でドラゴン戦→下山）、犬は場面に応じて喜怒哀楽の表情を切り替える。
/// 装備（麦わら帽子→水筒→剣→マフラー→宇宙ヘルメット→マント）は各々次のステージで
/// 役に立ち（剣はドラゴン戦・グレイ戦で構え、ヘルメットは宇宙で身を守る）、
/// 全面踏破後のゴールでは全装備の勇者としてお祝いする。
/// ADR 0010: TimelineView が渡す date のみを入力に取る純関数で状態を導出する
/// （Timer / repeatForever / body 内 mutate は禁止）。
enum CompactingDogAnimation {
    // MARK: 時間軸（イベント中はスクロールが止まる）

    /// 1ステージ（秒）。スクロール時間 11.0 秒＋停止イベント（イベント1 1.8・イベント2 1.4）。
    /// ステージに旗は無く、イベント後は走り抜けてそのまま次のステージへ続く。
    static let stageDuration: TimeInterval = 14.2
    static let event1Window: (start: TimeInterval, duration: TimeInterval) = (5.4, 1.8)
    static let event2Window: (start: TimeInterval, duration: TimeInterval) = (9.2, 1.4)

    /// ゴール区間（全5ステージ踏破後に1回だけ）: 旗が現れるまで走り →
    /// 旗の前でお祝いホップ → 走り出して第1面へ周回する。
    static let goalRunIn: TimeInterval = 1.6
    static let goalCelebrate: TimeInterval = 2.0
    static let goalRunOut: TimeInterval = 0.6
    static var goalDuration: TimeInterval { goalRunIn + goalCelebrate + goalRunOut }
    /// 大周期 = 全5ステージ + ゴール区間。
    static var grandPeriod: TimeInterval { stageDuration * Double(Stage.allCases.count) + goalDuration }

    /// スクロール速度（pt/秒）。
    static let scrollSpeed: Double = 90
    /// 犬の画面上の固定 x（pt）。
    static let dogScreenX: Double = 40

    // MARK: 世界座標（screenX = worldX - offset で描画）

    /// イベント1の相手が犬の正面（screen 111pt）で待つ配置（τ=5.4 到着）。
    static let actor1WorldX: Double = 597
    /// イベント2の相手・ご褒美の配置（τ=7.4 到着）。
    static let actor2WorldX: Double = 774
    /// ゴール区間の旗（ゴール走行 τ=goalRunIn で犬の正面 112pt に到着する配置）。
    static let goalFlagWorldX: Double = 256

    /// ジャンプ窓の半幅（秒）。月は低重力でふわりと長く滞空する。
    static func jumpHalfWidth(for stage: Stage) -> TimeInterval {
        stage == .moon ? 0.7 : 0.4
    }

    /// ジャンプ高さの倍率。月は低重力で高く跳ぶ。
    static func jumpBoost(for stage: Stage) -> Double {
        stage == .moon ? 1.25 : 1
    }

    /// 戦闘イベント冒頭の「驚き（哀）」の長さ（秒）。以降は「怒」で立ち向かう。
    static let fightStartleDuration: TimeInterval = 0.5

    /// 犬の喜怒哀楽。relaxed=楽（走行中のすまし顔）/ joyful=喜（友達・ご褒美・お祝い）/
    /// angry=怒（戦闘）/ startled=哀（戦闘の出会い頭の驚き）。
    enum Emotion: Equatable {
        case relaxed
        case joyful
        case angry
        case startled
    }

    /// 成長の装備。各ステージのイベント2で1つずつ獲得し、大周期の間は身に着けたまま
    /// 進む（周回すると初心に戻って装備リセット）。各装備は**次のステージで役に立つ**:
    /// 海の宝箱=麦わら帽子（川の雨日よけ）/ 川のカエル=水筒（砂漠の水分補給）/
    /// 砂漠のオアシス=伝説の剣（火山のドラゴン戦・宇宙のグレイ戦で構える）/
    /// 火山の温泉=マフラー（氷山の防寒）/ 氷山のイグルー=宇宙ヘルメット（宇宙で
    /// 身を守る）/ 宇宙のUFO=勇者のマント（ゴールの晴れ姿）。
    enum Equipment: Int, CaseIterable, Equatable {
        case strawHat
        case flask
        case sword
        case scarf
        case helmet
        case cape
    }

    /// そのステージのクリア報酬（イベント2で獲得する装備）。
    static func stageReward(_ stage: Stage) -> Equipment {
        Equipment(rawValue: stage.rawValue)!
    }

    /// そのステージ時点で身に着けている装備（クリア済みステージの報酬＋
    /// 自ステージ分はイベント2の終了後から）。
    static func ownedEquipment(stage: Stage, t: TimeInterval) -> [Equipment] {
        let count = stage.rawValue + (t >= event2Window.start + event2Window.duration ? 1 : 0)
        return Array(Equipment.allCases.prefix(count))
    }

    /// イベント2の最中に獲得しつつある装備（点滅の獲得演出用）。窓の外は nil。
    static func acquiringEquipment(stage: Stage, t: TimeInterval) -> Equipment? {
        t >= event2Window.start && t < event2Window.start + event2Window.duration
            ? stageReward(stage)
            : nil
    }

    /// 水中ステージか（犬は走らず犬掻きで泳ぐ）。
    static func isUnderwater(_ stage: Stage) -> Bool {
        stage == .sea
    }

    /// 水中の上昇気泡の底からの高さ（pt）。index ごとに位相をずらし、一定速度で
    /// 上昇して span（シーン高さ＋余白）で下へ巻き戻る純関数。
    static func risingBubbleAscent(elapsed: TimeInterval, index: Int, span: Double) -> Double {
        let speed = 16.0
        let phase = Double(index) * 37.0
        return (max(elapsed, 0) * speed + phase).truncatingRemainder(dividingBy: span)
    }

    // MARK: 地形（上り坂・下り坂）

    /// 台形プロファイルの丘（上り坂 → 頂上の平場 → 下り坂）。座標は世界座標（pt）、
    /// height は地面からの高さ（pt）。
    struct Hill: Equatable {
        let footStart: Double
        let topStart: Double
        let topEnd: Double
        let footEnd: Double
        let height: Double
    }

    /// ステージごとの地形。障害物のジャンプ地点（〜400pt）とは重ねない。
    /// 火山は大きな山: 登坂 → 山頂の平場でドラゴン戦（597）と温泉（774）→ 下山。
    /// 月のクレーターは地形ではなくスプライト（障害物＋地表の装飾）で表現する。
    static func hills(for stage: Stage) -> [Hill] {
        switch stage {
        case .sea, .river, .moon:
            []
        case .desert:
            [
                Hill(footStart: 410, topStart: 465, topEnd: 465, footEnd: 520, height: 6),
                Hill(footStart: 640, topStart: 700, topEnd: 700, footEnd: 760, height: 6),
            ]
        case .volcano:
            [Hill(footStart: 420, topStart: 540, topEnd: 810, footEnd: 950, height: 12)]
        case .ice:
            [Hill(footStart: 760, topStart: 830, topEnd: 830, footEnd: 900, height: 8)]
        }
    }

    /// 世界座標 worldX の地面の高さ（pt）。丘は重ならない前提で最初の一致を返す。
    static func elevation(stage: Stage, worldX: Double) -> Double {
        for hill in hills(for: stage) where worldX > hill.footStart && worldX < hill.footEnd {
            if worldX < hill.topStart {
                return hill.height * (worldX - hill.footStart) / (hill.topStart - hill.footStart)
            }
            if worldX <= hill.topEnd {
                return hill.height
            }
            return hill.height * (hill.footEnd - worldX) / (hill.footEnd - hill.topEnd)
        }
        return 0
    }

    /// イベントの演出種別。fight=星を散らして戦う / friend=ハートで挨拶 /
    /// reward=キラキラ＋ハートのご褒美。
    enum EventKind: Equatable {
        case fight
        case friend
        case reward
    }

    /// ステージ固有の物語（台本）。ジャンプの回数・時刻とイベントの種別を差し替える。
    struct StageScript: Equatable {
        let jumpArrivals: [TimeInterval]
        let event1: EventKind
        let event2: EventKind
        /// event1 の相手が終了後に居なくなるか（退治した・捕まえた・泳ぎ去った）。
        let actor1Leaves: Bool
    }

    /// 各ステージの物語:
    /// 海=イルカと挨拶→宝箱 / 川=魚を捕まえる→カエルの友達 / 砂漠=サソリ戦→オアシス /
    /// 火山=ドラゴン戦→温泉 / 氷山=ペンギンの友達→イグルー /
    /// 月=グレイ（宇宙人）戦→UFOでマント発見。
    static func script(for stage: Stage) -> StageScript {
        switch stage {
        case .sea:
            StageScript(jumpArrivals: [1.8], event1: .friend, event2: .reward, actor1Leaves: true)
        case .river:
            StageScript(jumpArrivals: [1.2, 2.4, 3.6], event1: .reward, event2: .friend, actor1Leaves: true)
        case .desert:
            StageScript(jumpArrivals: [1.8, 3.6], event1: .fight, event2: .reward, actor1Leaves: true)
        case .volcano:
            StageScript(jumpArrivals: [1.8, 3.6], event1: .fight, event2: .reward, actor1Leaves: true)
        case .ice:
            StageScript(jumpArrivals: [1.4, 2.6, 3.8], event1: .friend, event2: .reward, actor1Leaves: false)
        case .moon:
            // 低重力の長い滞空（半幅 0.7s）に合わせてジャンプ間隔を広く取る。
            StageScript(jumpArrivals: [1.5, 3.4], event1: .fight, event2: .reward, actor1Leaves: true)
        }
    }

    /// 障害物の世界座標（ジャンプ頂点で犬の中央の真下に来る位置）。
    static func obstacleWorldX(jumpArrival: TimeInterval) -> Double {
        dogScreenX + 32 + scrollSpeed * jumpArrival
    }

    /// ステージ（1サイクルごとにこの順でローテーション）。
    enum Stage: Int, CaseIterable, Equatable {
        case sea
        case river
        case desert
        case volcano
        case ice
        case moon
    }

    enum Phase: Equatable {
        case running
        case event1
        case event2
        case celebrating
    }

    struct SceneState: Equatable {
        /// 世界のスクロール量（pt）。screenX = worldX - offset。
        var offset: Double
        /// ジャンプ/ホップ高さ（0=接地, 1=頂点）。
        var jumpHeight: Double
        /// 走りアニメのフレーム（0/1。停止イベント中は 0 固定）。
        var runFrame: Int
        /// エフェクト点滅フレーム（0/1）。
        var effectFrame: Int
        var phase: Phase
        /// イベント1の相手が画面に居るか（台本の actor1Leaves ならイベント後に消える）。
        var actor1Visible: Bool
        /// 犬の表情（喜怒哀楽）。
        var emotion: Emotion
        /// 水中ステージで犬掻き中か（走りの代わりに泳ぎフレームを使う）。
        var isSwimming: Bool
        /// 犬掻きの上下の揺れ（pt。水中以外は 0）。
        var swimBob: Double
    }

    /// 進行区間: ステージ5面（各 stageDuration）が連続し、最後にゴール区間、そして周回。
    enum Segment: Equatable {
        case stage(Stage, t: TimeInterval)
        case goal(t: TimeInterval)
    }

    /// 圧縮開始からの経過秒を大周期に正規化し、現在の区間と区間内経過秒を返す。
    /// 決定論（elapsed のみ入力）。圧縮のたびに第1面の頭から始まる。
    static func segment(elapsed: TimeInterval) -> Segment {
        let normalized = max(elapsed, 0).truncatingRemainder(dividingBy: grandPeriod)
        let stagesSpan = stageDuration * Double(Stage.allCases.count)
        if normalized < stagesSpan {
            let index = min(Int(normalized / stageDuration), Stage.allCases.count - 1)
            return .stage(Stage.allCases[index], t: normalized - Double(index) * stageDuration)
        }
        return .goal(t: normalized - stagesSpan)
    }

    /// 実時間 t から「スクロールが進んだ時間」τ を導出する（停止イベント中は進まない）。
    static func scrollTime(at t: TimeInterval) -> TimeInterval {
        let clamped = min(max(t, 0), stageDuration)
        var tau = clamped
        for window in [event1Window, event2Window] {
            if clamped >= window.start + window.duration {
                tau -= window.duration
            } else if clamped > window.start {
                tau -= clamped - window.start
            }
        }
        return tau
    }

    static func phase(at t: TimeInterval) -> Phase {
        if t >= event1Window.start, t < event1Window.start + event1Window.duration { return .event1 }
        if t >= event2Window.start, t < event2Window.start + event2Window.duration { return .event2 }
        return .running
    }

    /// 場面から表情（喜怒哀楽）を導出する。戦闘は「驚き（哀）→怒って立ち向かう」の
    /// 二拍で、友達・ご褒美は喜、走行中は楽（すまし顔）。
    static func emotion(at t: TimeInterval, script: StageScript) -> Emotion {
        switch phase(at: t) {
        case .running:
            .relaxed
        case .event1:
            emotion(of: script.event1, eventElapsed: t - event1Window.start)
        case .event2:
            emotion(of: script.event2, eventElapsed: t - event2Window.start)
        case .celebrating:
            .joyful
        }
    }

    private static func emotion(of kind: EventKind, eventElapsed: TimeInterval) -> Emotion {
        switch kind {
        case .fight:
            eventElapsed < fightStartleDuration ? .startled : .angry
        case .friend, .reward:
            .joyful
        }
    }

    /// 障害物を跨ぐジャンプ（スクロール時刻 τ の窓で放物線）。
    static func obstacleJumpHeight(
        scrollTime tau: TimeInterval,
        arrivals: [TimeInterval],
        halfWidth: TimeInterval
    ) -> Double {
        for arrival in arrivals {
            let start = arrival - halfWidth
            let end = arrival + halfWidth
            if tau > start, tau < end {
                return sin((tau - start) / (end - start) * .pi)
            }
        }
        return 0
    }

    /// ステージ区間内の実時間 t からシーン全体を導出する純関数。
    static func scene(at t: TimeInterval, stage: Stage) -> SceneState {
        let script = script(for: stage)
        let underwater = isUnderwater(stage)
        let clamped = min(max(t, 0), stageDuration)
        let tau = scrollTime(at: clamped)
        let currentPhase = phase(at: clamped)
        let effectFrame = Int(clamped * 8).isMultiple(of: 2) ? 0 : 1

        var jumpHeight: Double = currentPhase == .running
            ? obstacleJumpHeight(
                scrollTime: tau,
                arrivals: script.jumpArrivals,
                halfWidth: jumpHalfWidth(for: stage)
            ) * jumpBoost(for: stage)
            : 0
        if stage == .moon, currentPhase == .running {
            // 低重力の跳ねる歩容: 地上走行でも常にふわりと弾んで進む。
            jumpHeight = max(jumpHeight, abs(sin(tau * .pi / 1.1)) * 0.3)
        }

        return SceneState(
            offset: scrollSpeed * tau,
            jumpHeight: jumpHeight,
            runFrame: (currentPhase == .running && jumpHeight == 0) || underwater
                ? (Int(clamped * 6).isMultiple(of: 2) ? 0 : 1)
                : 0,
            effectFrame: effectFrame,
            phase: currentPhase,
            actor1Visible: !script.actor1Leaves || clamped < event1Window.start + event1Window.duration,
            emotion: emotion(at: clamped, script: script),
            isSwimming: underwater,
            swimBob: underwater ? sin(clamped * 2 * .pi / 1.6) * 3 : 0
        )
    }

    /// ゴール区間のシーン: 旗へ走り（goalRunIn）→ 旗の前でお祝いホップ（スクロール停止）
    /// → 走り出して周回へ。
    static func goalScene(at t: TimeInterval) -> SceneState {
        let clamped = min(max(t, 0), goalDuration)
        let celebrateEnd = goalRunIn + goalCelebrate
        let tau = min(clamped, goalRunIn) + max(0, clamped - celebrateEnd)
        let isCelebrating = clamped >= goalRunIn && clamped < celebrateEnd
        let jumpHeight = isCelebrating
            ? abs(sin((clamped - goalRunIn) / goalCelebrate * .pi * 4)) * 0.5
            : 0

        return SceneState(
            offset: scrollSpeed * tau,
            jumpHeight: jumpHeight,
            runFrame: isCelebrating ? 0 : (Int(clamped * 6).isMultiple(of: 2) ? 0 : 1),
            effectFrame: Int(clamped * 8).isMultiple(of: 2) ? 0 : 1,
            phase: isCelebrating ? .celebrating : .running,
            actor1Visible: false,
            emotion: isCelebrating ? .joyful : .relaxed,
            isSwimming: false,
            swimBob: 0
        )
    }
}

// MARK: - ドット絵スプライト（行文字列 = 1px。文字→色は View 側のパレットで解決）

enum CompactingDogSprites {
    /// 白×グレーのぶち犬（3/4視点・26x20）。参考画像の特徴を反映:
    /// グレーの立ち耳・顔の片側（進行方向の反対側）のグレーのぶち・白目ハイライト入りの
    /// 丸い黒目・黒い鼻の下に開いた口とピンクの舌・お尻のグレーの模様・白いふわふわの胸。
    /// 'L'=輪郭, 'E'=グレーのぶち, 'W'=毛（白）, 'S'=毛の陰影, 'K'=目・鼻・口,
    /// 'T'=舌, 'P'=頬, '.'=透過。
    static let dogFrames: [[String]] = [
        [
            "..........LLLL....LLLL....",
            ".........LEEEELLLLEEEEL...",
            "..........LEEEWWWWWWWWWL..",
            ".........LEEEEEWWWWWWWWWL.",
            ".........LEEEEEWWWWWWWWWL.",
            ".........LEEEEWWWWWWWWWWL.",
            ".........LEEEEWWWWWWWWWWL.",
            ".........LEEEKKWWWWKKWWWL.",
            ".LLL.....LEEEKKWWWWKKWWWL.",
            "LWWWL....LWPPWWWKKWWWWPPL.",
            "LWWWL....LWWWWWWTTWWWWWWL.",
            "LWWWWL....LWWWWWWWWWWWWL..",
            ".LWWWL.LEEEWWWWWWWWWWWWL..",
            "..LSSLLEEEWWWWWWWWWWWWWL..",
            "......LEEWWWWWWWWSSSSSL...",
            "......LWWWWWWWSSSSSSL.....",
            ".......LWWWWLLLLWWWWL.....",
            "........LWWL....LWWL......",
            "........LWWL....LWWL......",
            "........LLLL....LLLL......",
        ],
        [
            "..........LLLL....LLLL....",
            ".........LEEEELLLLEEEEL...",
            "..........LEEEWWWWWWWWWL..",
            ".........LEEEEEWWWWWWWWWL.",
            ".........LEEEEEWWWWWWWWWL.",
            ".........LEEEEWWWWWWWWWWL.",
            ".........LEEEEWWWWWWWWWWL.",
            ".........LEEEKKWWWWKKWWWL.",
            ".LLL.....LEEEKKWWWWKKWWWL.",
            "LWWWL....LWPPWWWKKWWWWPPL.",
            "LWWWL....LWWWWWWTTWWWWWWL.",
            "LWWWWL....LWWWWWWWWWWWWL..",
            ".LWWWL.LEEEWWWWWWWWWWWWL..",
            "..LSSLLEEEWWWWWWWWWWWWWL..",
            "......LEEWWWWWWWWSSSSSL...",
            "......LWWWWWWWSSSSSSL.....",
            ".......LWWWWLLLLWWWWL.....",
            ".......LWWL......LWWL.....",
            "......LWWL........LWWL....",
            "......LLLL........LLLL....",
        ],
    ]

    /// 犬掻きフレーム（水中用）。頭・胴（0〜16行目）は走りフレームと同一に保ち、
    /// 表情・装備オーバーレイの座標互換を維持する。脚だけを掻き交互に差し替える。
    static let dogSwimFrames: [[String]] = [
        // 4本の短い脚（前2・後2）を交互に伸ばして掻く。
        Array(dogFrames[0][0..<17]) + [
            ".......LWL.LWL..LWL.LWL...",
            ".......LLL......LLL.......",
            "..........................",
        ],
        Array(dogFrames[0][0..<17]) + [
            ".......LWL.LWL..LWL.LWL...",
            "...........LLL......LLL...",
            "..........................",
        ],
    ]

    /// サソリ（砂漠・左向き 18x13）。犬と同じちび様式（輪郭・大きな瞳・頬）。
    /// 'L'=輪郭, 'N'=体, 'K'=目, 'P'=頬, 'Y'=毒針。左にハサミ、右上に巻いた尾。
    static let scorpionFrames: [[String]] = [
        [
            "...........LLL....",
            "..........LNNNL...",
            "........YYLNNNL...",
            ".........YLNNL....",
            "...........LNL....",
            "...LLLLLLL.LNL....",
            "..LNNNNNNNLLNL....",
            ".LWWKKNNNNNNNL....",
            ".LWWKKNNNNNNNL....",
            "LLNPPNNNNNNNL.....",
            "LNLNNNNNNNNNL.....",
            ".LLLNLLNLLNLL.....",
            "...LL..LL..LL.....",
        ],
        [
            "...........LLL....",
            "........YYLNNNL...",
            ".........YLNNNL...",
            "..........LNNL....",
            "...........LNL....",
            "...LLLLLLL.LNL....",
            "..LNNNNNNNLLNL....",
            ".LWWKKNNNNNNNL....",
            ".LWWKKNNNNNNNL....",
            "LLNPPNNNNNNNL.....",
            "LNLNNNNNNNNNL.....",
            ".LLLNLLNLLNLL.....",
            "...LL..LL..LL.....",
        ],
    ]

    /// ドラゴン（火山・左向き 20x17）。'L'=輪郭, 'R'=体, 'Y'=腹・角, 'K'=目, 'W'=翼膜。
    /// 2フレームで翼をはばたく。
    static let dragonFrames: [[String]] = [
        [
            "..LL...LL...........",
            ".LYYL.LYYL....LLL...",
            ".LRRLLLRRL...LWWLL..",
            "LRRRRRRRRRL.LWWWWL..",
            "LRRRRRRRRRRLLWWWL...",
            "LRKKRRRRRRRRLWWL....",
            "LRKKRRRRRRRRRLL.....",
            "LRRRRRRRRRRRRRL.....",
            ".LRRRRRRRRRRRRRL....",
            ".LRYYYYYRRRRRRRL....",
            "LRRYYYYYRRRRRRRRL...",
            "LRRYYYYYRRRRRRRL....",
            "LRRYYYYYRRRRRRLRRL..",
            ".LRRYYYRRRRRRRLLRRL.",
            ".LRRRRRRRRRRRL..LL..",
            "..LRRLLLLRRL........",
            "..LLLL..LLLL........",
        ],
        [
            "..LL...LL...........",
            ".LYYL.LYYL..........",
            ".LRRLLLRRL..........",
            "LRRRRRRRRRL..LL.....",
            "LRRRRRRRRRRLLWWL....",
            "LRKKRRRRRRRRLWWWL...",
            "LRKKRRRRRRRRRWWWWL..",
            "LRRRRRRRRRRRRRLLL...",
            ".LRRRRRRRRRRRRRL....",
            ".LRYYYYYRRRRRRRL....",
            "LRRYYYYYRRRRRRRRL...",
            "LRRYYYYYRRRRRRRL....",
            "LRRYYYYYRRRRRRLRRL..",
            ".LRRYYYRRRRRRRLLRRL.",
            ".LRRRRRRRRRRRL..LL..",
            "..LRRLLLLRRL........",
            "..LLLL..LLLL........",
        ],
    ]

    // MARK: ステージ別の障害物

    /// サボテン（砂漠・6x8）。'G'=緑。
    static let cactus: [String] = [
        "..GG..",
        "..GG..",
        "G.GG.G",
        "G.GG.G",
        "GGGGGG",
        "..GG..",
        "..GG..",
        "..GG..",
    ]

    /// サンゴ（海・7x6）。'M'=サンゴ色。
    static let coral: [String] = [
        ".M.M.M.",
        ".M.M.M.",
        ".MMMMM.",
        "...M...",
        "...M...",
        "..MMM..",
    ]

    /// 岩（川・8x4）。'C'=グレー。
    static let rock: [String] = [
        "..CCCC..",
        ".CCCCCC.",
        "CCCCCCCC",
        "CCCCCCCC",
    ]

    /// 溶岩岩（火山・8x4）。'V'=黒岩, 'R'=赤い亀裂。
    static let lavaRock: [String] = [
        "..VVVV..",
        ".VVRVVV.",
        "VVVRVVVV",
        "VVVVVVVV",
    ]

    /// 氷柱（氷山・7x6）。'I'=氷。
    static let iceSpike: [String] = [
        "...I...",
        "..III..",
        "..III..",
        ".IIIII.",
        ".IIIII.",
        "IIIIIII",
    ]

    // MARK: ステージ別の空の演出

    /// 雲（砂漠/川・12x4）。'C'=雲。
    static let cloud: [String] = [
        "...CCCCC....",
        ".CCCCCCCCC..",
        "CCCCCCCCCCC.",
        "..CCCCCC....",
    ]

    /// 泡（海・5x5）。'B'=泡。
    static let bubble: [String] = [
        ".BBB.",
        "B...B",
        "B...B",
        "B...B",
        ".BBB.",
    ]

    /// 火の粉（火山・3x3）。'Y'=黄, 'R'=赤。
    static let ember: [String] = [
        ".Y.",
        "YRY",
        ".R.",
    ]

    /// 雪片（氷山・5x5）。'S'=雪。
    static let snowflake: [String] = [
        "..S..",
        "S.S.S",
        ".SSS.",
        "S.S.S",
        "..S..",
    ]

    // MARK: 共通の小物

    /// 戦闘エフェクト（星 5x5）。'Y'=黄。
    static let star: [String] = [
        "..Y..",
        "..Y..",
        "YYYYY",
        "..Y..",
        "..Y..",
    ]

    /// イルカ（海・左向き 18x12）。ちび様式: 輪郭・大きな瞳・頬・白い腹・背びれ・尾びれ。
    static let dolphin: [String] = [
        "......LL..........",
        ".....LBBL.........",
        "...LLBBBBLL.......",
        "..LBBBBBBBBLL.....",
        ".LBBBBBBBBBBBLL...",
        ".LBKKBBBBBBBBBBL..",
        "LBBKKBBBBBBBBBBL..",
        "LBBBBBBBBBBBBBBLL.",
        "LBPPBWWWWWBBBBBLBL",
        ".LBBWWWWWWBBBLLBBL",
        "..LLWWWWWBBBL..LL.",
        "....LLLLLLLL......",
    ]

    /// 宝箱（海・10x8）。'N'=木, 'Y'=金具。
    static let treasureChest: [String] = [
        "..NNNNNN..",
        ".NNNNNNNN.",
        "NNNNNNNNNN",
        "YYYYYYYYYY",
        "NNNNYYNNNN",
        "NNNNYYNNNN",
        "NNNNNNNNNN",
        "NNNNNNNNNN",
    ]

    /// 跳ねる魚（川・左向き 13x9）。ちび様式: 輪郭・大きな瞳・頬・尾びれ。
    static let fish: [String] = [
        "...LLLL......",
        "..LFFFFL..LL.",
        ".LFFFFFFLLFL.",
        "LFKKFFFFFFFL.",
        "LFKKFFFFFFFFL",
        "LFPPFWWFFFFL.",
        ".LFFWWWFLLFL.",
        "..LFFFFL..LL.",
        "...LLLL......",
    ]

    /// カエル（川・正面 14x11）。ちび様式: 頭の上の大きな目・頬・白い腹。
    static let frog: [String] = [
        ".LLLL....LLLL.",
        "LWWKKL..LKKWWL",
        "LWWKKLLLLKKWWL",
        ".LGGGGGGGGGGL.",
        "LGGGGGGGGGGGGL",
        "LGPPGGGGGGPPGL",
        "LGGWWWWWWWWGGL",
        "LGGWWWWWWWWGGL",
        ".LGGWWWWWWGGL.",
        ".LGGLLLLLLGGL.",
        "..LL......LL..",
    ]

    /// オアシス（砂漠・14x8）。'G'=ヤシの葉, 'N'=幹, 'B'=水。
    static let oasis: [String] = [
        "...GGG........",
        ".GGGGGGG......",
        "GGG.NN.GGG....",
        "....NN........",
        "....NN........",
        "...BBBBBB.....",
        ".BBBBBBBBBB...",
        "BBBBBBBBBBBB..",
    ]

    /// 温泉（火山・14x7）。'V'=岩, 'B'=湯, 'W'=湯気。
    static let hotSpring: [String] = [
        "..W....W......",
        "...W....W.....",
        "..W....W......",
        "VVVVVVVVVVVV..",
        "VBBBBBBBBBBV..",
        "VBBBBBBBBBBV..",
        "VVVVVVVVVVVV..",
    ]

    /// ペンギン（氷山・正面 12x14）。ちび様式: 白い顔と腹・大きな瞳・頬・小さな羽。
    /// 'V'=黒い羽毛, 'W'=顔・腹, 'K'=目, 'P'=頬, 'Y'=くちばし・足。
    static let penguin: [String] = [
        "...LLLLLL...",
        "..LVVVVVVL..",
        ".LVWWWWWWVL.",
        ".LVWKKWKKVL.",
        ".LVWKKWKKVL.",
        "LVWPPWWWPPVL",
        "LVWWWYYWWWVL",
        "LVWWWWWWWWVL",
        "LVVWWWWWWVVL",
        "LVVWWWWWWVVL",
        ".LVWWWWWWVL.",
        ".LVVWWWWVVL.",
        "..LLYYLYYLL.",
        "....LL..LL..",
    ]

    /// グレイ（月・宇宙人 14x16）。ちび様式: 大きな頭・黒いアーモンド形の目。
    /// 'L'=輪郭, 'E'=グレーの肌, 'K'=目・口。2フレームで腕を振る。
    static let greyFrames: [[String]] = [
        [
            "....LLLLLL....",
            "..LLEEEEEELL..",
            ".LEEEEEEEEEEL.",
            ".LEEEEEEEEEEL.",
            "LEKKKEEEEKKKEL",
            "LEKKKKEEKKKKEL",
            ".LEKKEEEEKKEL.",
            ".LEEEEEEEEEEL.",
            "..LEEEKKEEEL..",
            "...LLEEEELL...",
            "....LEEEEL....",
            "..LLEEEEEELL..",
            ".LEELEEEELEEL.",
            ".LL.LEEEEL.LL.",
            "....LELLEL....",
            "....LL..LL....",
        ],
        [
            "....LLLLLL....",
            "..LLEEEEEELL..",
            ".LEEEEEEEEEEL.",
            ".LEEEEEEEEEEL.",
            "LEKKKEEEEKKKEL",
            "LEKKKKEEKKKKEL",
            ".LEKKEEEEKKEL.",
            ".LEEEEEEEEEEL.",
            "..LEEEKKEEEL..",
            "...LLEEEELL...",
            ".LL.LEEEEL.LL.",
            ".LEELEEEELEEL.",
            "..LLEEEEEELL..",
            "....LEEEEL....",
            "....LELLEL....",
            "....LL..LL....",
        ],
    ]

    /// UFO（月・16x10）。グレイの乗り物。'I'=ガラスドーム, 'C'=銀の船体, 'Y'=ライト。
    static let ufo: [String] = [
        ".....LLLLL......",
        "....LIIIIIL.....",
        "...LIIWWIIIL....",
        "..LLLLLLLLLLL...",
        ".LCCCCCCCCCCCL..",
        "LCYCCYCCYCCYCCL.",
        ".LCCCCCCCCCCCL..",
        "..LLLLLLLLLLL...",
        "....LL...LL.....",
        "...LL.....LL....",
    ]

    /// 月面の大クレーター（障害物・14x4）。縁の盛り上がり2つと暗い窪み。
    static let moonCrater: [String] = [
        ".CCC......CCC.",
        "CCVCC....CCVCC",
        "CVVVCCCCCCVVVC",
        "CVVVVVVVVVVVVC",
    ]

    /// 月面の小クレーター（地表の装飾・8x2）。
    static let moonCraterSmall: [String] = [
        ".CCCCCC.",
        "CVVVVVVC",
    ]

    /// 星の瞬き（月の空・3x3）。'Y'=黄, 'W'=白。
    static let starTwinkle: [String] = [
        ".Y.",
        "YWY",
        ".Y.",
    ]

    /// 空に浮かぶ地球（月・9x8）。'B'=海, 'G'=大陸。
    static let earth: [String] = [
        "..LLLLL..",
        ".LBBGGBL.",
        "LBBGGBBBL",
        "LBGGBBBGL",
        "LBBBBGGBL",
        "LBBGGGBBL",
        ".LBBGBBL.",
        "..LLLLL..",
    ]

    /// イグルー（氷山・14x7）。'W'=雪ブロック, 'S'=目地, 'K'=入口。
    static let igloo: [String] = [
        "....WWWWWW....",
        "..WWWWWWWWWW..",
        ".WWWSSWWSSWWW.",
        "WWWWWWWWWWWWWW",
        "WWKKWWWWWWWWWW",
        "WWKKWWWWWWWWWW",
        "WWKKWWWWWWWWWW",
    ]

    // MARK: 犬の表情・装備オーバーレイ（犬スプライトのピクセル座標系。x/y は左上オフセット）

    /// 犬の上に重ねるオーバーレイ。オフセットは犬スプライトの左上を原点とする
    /// ピクセル座標（負値は犬の外側＝頭上・背後）。
    struct DogOverlay {
        let rows: [String]
        let x: Int
        let y: Int
    }

    /// 喜: 目（2x2）を閉じた笑顔の線（2x1）に置き換える。
    static let happyEyes = DogOverlay(rows: ["KK....KK", "EW....WW"], x: 13, y: 7)

    /// 怒: 目の上の中央へつり下がる眉。
    static let angryBrows = DogOverlay(rows: ["K......K", ".K....K."], x: 13, y: 5)

    /// 哀（驚き）: 頭の横に浮かぶ汗のしずく。
    static let sweatDrop = DogOverlay(rows: [".B.", "BBB", "BBB"], x: 24, y: 1)

    /// 犬掻き中に口元から立ちのぼる泡（点滅フレームで描く）。
    static let swimBubbles = DogOverlay(rows: ["B.", ".B", "B."], x: 26, y: 4)

    /// ドラゴン戦で構える剣（剣を所持している戦闘中、背負い剣の代わりに前方へ構える）。
    static let brandishedSword = DogOverlay(rows: [
        "....CC",
        "....CC",
        "...CC.",
        "...CC.",
        "..YY..",
        "..NN..",
    ], x: 23, y: 0)

    /// 装備のオーバーレイ。behind=true は犬より奥（背負う剣・なびくマント）。
    static func equipmentOverlay(
        _ equipment: CompactingDogAnimation.Equipment
    ) -> (overlay: DogOverlay, behind: Bool) {
        switch equipment {
        case .strawHat:
            // 海の宝箱で見つける麦わら帽子（次の川の雨日よけ）。'N'=帯。
            (DogOverlay(rows: [
                "...YYYYY....",
                "..YNNNNNY...",
                "YYYYYYYYYYYY",
            ], x: 11, y: -2), false)
        case .flask:
            // 川のカエルにもらう水筒（次の砂漠の水分補給）。腰に提げる。
            (DogOverlay(rows: [
                ".NN.",
                "NBBN",
                "NBBN",
                ".NN.",
            ], x: 8, y: 13), false)
        case .sword:
            // 背に斜めに背負う剣。柄の根元（最下2行）が背中のシルエットに重なって
            // 「浮いて見えない」よう、犬の (r12-13, c5-6) まで届かせる。
            (DogOverlay(rows: [
                "CC....",
                "CC....",
                ".CC...",
                ".CC...",
                "..CC..",
                ".YYYY.",
                "...NN.",
                "...NN.",
                "...NN.",
                "...NN.",
            ], x: 2, y: 4), true)
        case .scarf:
            // 火山の温泉で手に入れる赤いマフラー（次の氷山の防寒）。太めに巻いて
            // 端が後方へ長くなびく。
            (DogOverlay(rows: [
                "....RRRRRRRRRRRR",
                "....RRRRRRRRRRRR",
                ".RRR............",
                "RRR.............",
                "RRR.............",
                ".RR.............",
            ], x: 7, y: 11), false)
        case .helmet:
            // 頭を包むガラスの宇宙ヘルメット（輪郭のリング＋左上のハイライト）。
            // 麦わら帽子ごと頭をすっぽり覆う。
            (DogOverlay(rows: [
                "......IIIIIIIII......",
                "....II.........II....",
                "...I.WW..........I...",
                "..I..W............I..",
                ".I.................I.",
                ".I.................I.",
                "I...................I",
                "I...................I",
                "I...................I",
                "I...................I",
                ".I.................I.",
                ".I.................I.",
                "..I...............I..",
                "...I.............I...",
                "....II.........II....",
                "......II.....II......",
                "........IIIII........",
            ], x: 7, y: -3), false)
        case .cape:
            // 背中から左へなびく勇者の青いマント（ゴールの晴れ姿）。
            (DogOverlay(rows: [
                "....UUU",
                "...UUUU",
                "..UUUUU",
                ".UUUUUU",
                "UUUUUU.",
                "UUUUU..",
                "UUUU...",
                ".UUU...",
            ], x: -3, y: 8), true)
        }
    }

    /// 食事・お祝いのハート（6x5）。'P'=ピンク。
    static let heart: [String] = [
        ".PP.PP",
        "PPPPPP",
        "PPPPPP",
        ".PPPP.",
        "..PP..",
    ]

    /// ゴール旗（12x16）。'L'=ポール, 'R'=旗。
    static let flag: [String] = [
        "LRRRRRR.....",
        "LRRRRR......",
        "LRRRR.......",
        "LRRR........",
        "LRR.........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "L...........",
        "LLL.........",
    ]
}

/// ドット絵サイドスクロールの描画。Canvas に 1px=pixelSize の矩形でスプライトを敷く。
struct CompactingDogSceneView: View {
    let date: Date
    /// 圧縮開始時刻（セル出現時に固定）。物語とステージ進行の起点。
    let startDate: Date

    private static let pixelSize: CGFloat = 2.5
    static let sceneWidth: CGFloat = 280
    /// 月の低重力ジャンプ（1.25倍）＋宇宙ヘルメット（頭上3px）でも見切れない高さ。
    static let sceneHeight: CGFloat = 96
    /// 地面の y（Canvas 座標。スプライトの足元がここに接地する）。
    private static let groundY: CGFloat = 88
    private static let jumpPixels: CGFloat = 24
    /// 空の演出のパララックス係数（背景は前景よりゆっくり流れる）。
    private static let skyParallax: CGFloat = 0.35
    private static let skyWrapSpan: CGFloat = 400

    /// ステージごとの見た目（背景色・障害物・空の演出・イベントの相手・地面の色）。
    private struct StageTheme {
        let skyTint: Color
        let obstacle: [String]
        let skyProp: [String]
        /// イベント1の相手（点滅2フレーム。1枚なら同じものを2回入れる）。
        let actor1Frames: [[String]]
        /// イベント2の相手・ご褒美（居続ける）。
        let actor2: [String]
        let groundDot: Color
    }

    private static func theme(for stage: CompactingDogAnimation.Stage) -> StageTheme {
        switch stage {
        case .sea:
            StageTheme(
                skyTint: Color(red: 0.12, green: 0.24, blue: 0.42),
                obstacle: CompactingDogSprites.coral,
                skyProp: CompactingDogSprites.bubble,
                actor1Frames: [CompactingDogSprites.dolphin, CompactingDogSprites.dolphin],
                actor2: CompactingDogSprites.treasureChest,
                groundDot: Color(red: 0.38, green: 0.58, blue: 0.82)
            )
        case .river:
            StageTheme(
                skyTint: Color(red: 0.10, green: 0.30, blue: 0.30),
                obstacle: CompactingDogSprites.rock,
                skyProp: CompactingDogSprites.cloud,
                actor1Frames: [CompactingDogSprites.fish, CompactingDogSprites.fish],
                actor2: CompactingDogSprites.frog,
                groundDot: Color(red: 0.42, green: 0.68, blue: 0.70)
            )
        case .desert:
            StageTheme(
                skyTint: Color(red: 0.38, green: 0.30, blue: 0.14),
                obstacle: CompactingDogSprites.cactus,
                skyProp: CompactingDogSprites.cloud,
                actor1Frames: CompactingDogSprites.scorpionFrames,
                actor2: CompactingDogSprites.oasis,
                groundDot: Color(red: 0.78, green: 0.66, blue: 0.42)
            )
        case .volcano:
            StageTheme(
                skyTint: Color(red: 0.34, green: 0.11, blue: 0.09),
                obstacle: CompactingDogSprites.lavaRock,
                skyProp: CompactingDogSprites.ember,
                actor1Frames: CompactingDogSprites.dragonFrames,
                actor2: CompactingDogSprites.hotSpring,
                groundDot: Color(red: 0.86, green: 0.44, blue: 0.22)
            )
        case .ice:
            StageTheme(
                skyTint: Color(red: 0.16, green: 0.27, blue: 0.40),
                obstacle: CompactingDogSprites.iceSpike,
                skyProp: CompactingDogSprites.snowflake,
                actor1Frames: [CompactingDogSprites.penguin, CompactingDogSprites.penguin],
                actor2: CompactingDogSprites.igloo,
                groundDot: Color(red: 0.68, green: 0.82, blue: 0.94)
            )
        case .moon:
            StageTheme(
                skyTint: Color(red: 0.05, green: 0.06, blue: 0.16),
                obstacle: CompactingDogSprites.moonCrater,
                skyProp: CompactingDogSprites.starTwinkle,
                actor1Frames: CompactingDogSprites.greyFrames,
                actor2: CompactingDogSprites.ufo,
                groundDot: Color(white: 0.78)
            )
        }
    }

    var body: some View {
        let elapsed = date.timeIntervalSince(startDate)
        Canvas { context, size in
            switch CompactingDogAnimation.segment(elapsed: elapsed) {
            case .stage(let stage, let t):
                drawStage(stage: stage, t: t, context: context, size: size)
            case .goal(let t):
                drawGoal(t: t, context: context, size: size)
            }
        }
        .frame(width: Self.sceneWidth, height: Self.sceneHeight)
        .clipped()
        .accessibilityIdentifier("CompactingIndicatorCell.dogAnimation")
    }

    private func drawStage(stage: CompactingDogAnimation.Stage, t: TimeInterval, context: GraphicsContext, size: CGSize) {
        let script = CompactingDogAnimation.script(for: stage)
        let scene = CompactingDogAnimation.scene(at: t, stage: stage)
        let theme = Self.theme(for: stage)
        context.fill(
            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
            with: .color(theme.skyTint.opacity(0.45))
        )
        // 水中（海）は横に流れる空の演出の代わりに、下から上へ立ちのぼる気泡で
        // 「水の中」を伝える。
        if CompactingDogAnimation.isUnderwater(stage) {
            drawRisingBubbles(t: t, context: context, size: size)
        } else {
            drawSkyProps(context: context, size: size, scene: scene, theme: theme)
        }
        if stage == .moon {
            // 遠景の地球（視差なしの静止）と、地表の小クレーター。
            drawSprite(CompactingDogSprites.earth, bottomLeftX: 214, bottomY: 30, context: context)
            for worldX: Double in [120, 300, 520, 700, 880] {
                drawWorldSprite(CompactingDogSprites.moonCraterSmall, worldX: worldX, context: context, size: size, scene: scene, stage: stage)
            }
        }
        drawGround(context: context, size: size, scene: scene, stage: stage, dotColor: theme.groundDot.opacity(0.65))
        for arrival in script.jumpArrivals {
            drawWorldSprite(
                theme.obstacle,
                worldX: CompactingDogAnimation.obstacleWorldX(jumpArrival: arrival),
                context: context,
                size: size,
                scene: scene,
                stage: stage
            )
        }
        drawWorldSprite(theme.actor2, worldX: CompactingDogAnimation.actor2WorldX, context: context, size: size, scene: scene, stage: stage)
        if scene.actor1Visible {
            let frame = theme.actor1Frames[scene.effectFrame]
            drawWorldSprite(frame, worldX: CompactingDogAnimation.actor1WorldX, context: context, size: size, scene: scene, stage: stage)
        }
        let owned = CompactingDogAnimation.ownedEquipment(stage: stage, t: t)
        drawDog(
            context: context,
            scene: scene,
            equipment: owned,
            acquiring: CompactingDogAnimation.acquiringEquipment(stage: stage, t: t),
            groundLift: CGFloat(CompactingDogAnimation.elevation(
                stage: stage,
                worldX: CompactingDogAnimation.dogScreenX + scene.offset
            )),
            // 剣を持っていれば戦闘（火山のドラゴン戦）で構える。砂漠のサソリ戦は
            // 剣の入手前なので素手＝装備が物語を変える。
            brandishesSword: scene.phase == .event1 && script.event1 == .fight && owned.contains(.sword)
        )
        drawEffects(context: context, scene: scene, script: script)
    }

    /// 全5ステージ踏破後のゴール: 金色がかった背景に旗が現れ、犬がお祝いする。
    private func drawGoal(t: TimeInterval, context: GraphicsContext, size: CGSize) {
        let scene = CompactingDogAnimation.goalScene(at: t)
        context.fill(
            Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8),
            with: .color(Color(red: 0.36, green: 0.30, blue: 0.10).opacity(0.40))
        )
        drawGround(context: context, size: size, scene: scene, dotColor: DSColor.chatTextSecondary.opacity(0.45))
        drawWorldSprite(CompactingDogSprites.flag, worldX: CompactingDogAnimation.goalFlagWorldX, context: context, size: size, scene: scene)
        // ゴールは全装備を身に着けた勇者の姿でお祝いする（成長物語の到達点）。
        drawDog(context: context, scene: scene, equipment: CompactingDogAnimation.Equipment.allCases)
        drawEffects(context: context, scene: scene, script: nil)
    }

    private func palette(_ character: Character) -> Color? {
        switch character {
        case "D": Color(red: 0.19, green: 0.40, blue: 0.17)
        case "L": Color(red: 0.44, green: 0.46, blue: 0.56)
        case "E": Color(red: 0.62, green: 0.63, blue: 0.72)
        case "W": Color(white: 0.97)
        case "S": Color(red: 0.80, green: 0.82, blue: 0.90)
        case "P": Color(red: 0.95, green: 0.71, blue: 0.69)
        case "T": Color(red: 0.88, green: 0.47, blue: 0.50)
        case "K": Color(white: 0.05)
        case "G": Color(red: 0.36, green: 0.65, blue: 0.32)
        case "M": Color(red: 0.90, green: 0.50, blue: 0.45)
        case "C": Color(white: 0.44)
        case "V": Color(white: 0.30)
        case "I": Color(red: 0.72, green: 0.85, blue: 0.95)
        case "B": Color(red: 0.55, green: 0.72, blue: 0.85)
        case "N": Color(red: 0.55, green: 0.38, blue: 0.20)
        case "F": Color(red: 0.95, green: 0.60, blue: 0.25)
        case "R": Color(red: 0.85, green: 0.32, blue: 0.30)
        case "Y": Color(red: 0.95, green: 0.78, blue: 0.20)
        case "U": Color(red: 0.35, green: 0.45, blue: 0.85)
        default: nil
        }
    }

    private func drawSprite(
        _ rows: [String],
        bottomLeftX: CGFloat,
        bottomY: CGFloat,
        context: GraphicsContext
    ) {
        let pixel = Self.pixelSize
        let topY = bottomY - CGFloat(rows.count) * pixel
        for (rowIndex, row) in rows.enumerated() {
            for (columnIndex, character) in row.enumerated() {
                guard let color = palette(character) else { continue }
                context.fill(
                    Path(CGRect(
                        x: bottomLeftX + CGFloat(columnIndex) * pixel,
                        y: topY + CGFloat(rowIndex) * pixel,
                        width: pixel,
                        height: pixel
                    )),
                    with: .color(color)
                )
            }
        }
    }

    /// 世界座標のスプライトをスクロール量ぶんずらし、地形の高さに接地させて描く
    /// （画面外はスキップ）。stage が nil のとき（ゴール区間）は平地。
    private func drawWorldSprite(
        _ rows: [String],
        worldX: Double,
        context: GraphicsContext,
        size: CGSize,
        scene: CompactingDogAnimation.SceneState,
        stage: CompactingDogAnimation.Stage? = nil
    ) {
        let screenX = CGFloat(worldX - scene.offset)
        let width = CGFloat(rows[0].count) * Self.pixelSize
        guard screenX > -width, screenX < size.width else { return }
        let lift = stage.map {
            CompactingDogAnimation.elevation(stage: $0, worldX: worldX + Double(width) / 2)
        } ?? 0
        drawSprite(rows, bottomLeftX: screenX, bottomY: Self.groundY - CGFloat(lift), context: context)
    }

    private func drawSkyProps(
        context: GraphicsContext,
        size: CGSize,
        scene: CompactingDogAnimation.SceneState,
        theme: StageTheme
    ) {
        for (baseX, topY) in [(CGFloat(60), CGFloat(4)), (CGFloat(230), CGFloat(14)), (CGFloat(360), CGFloat(2))] {
            var x = (baseX - CGFloat(scene.offset) * Self.skyParallax)
                .truncatingRemainder(dividingBy: Self.skyWrapSpan)
            if x < -40 { x += Self.skyWrapSpan }
            drawSprite(
                theme.skyProp,
                bottomLeftX: x,
                bottomY: topY + CGFloat(theme.skyProp.count) * Self.pixelSize,
                context: context
            )
        }
    }

    /// 水中の上昇気泡。画面に固定した水柱から小さな泡が揺らぎながら立ちのぼる。
    private func drawRisingBubbles(t: TimeInterval, context: GraphicsContext, size: CGSize) {
        let columns: [(x: CGFloat, side: CGFloat)] = [
            (24, 2), (66, 3), (108, 2), (150, 3), (196, 2), (244, 3),
        ]
        let span = Double(size.height) + 8
        for (index, column) in columns.enumerated() {
            let ascent = CompactingDogAnimation.risingBubbleAscent(elapsed: t, index: index, span: span)
            let wiggle = CGFloat(sin((t + Double(index)) * 2.4)) * 2
            context.fill(
                Path(ellipseIn: CGRect(
                    x: column.x + wiggle,
                    y: size.height - CGFloat(ascent),
                    width: column.side,
                    height: column.side
                )),
                with: .color(Color(red: 0.55, green: 0.72, blue: 0.85).opacity(0.55))
            )
        }
    }

    private func drawGround(
        context: GraphicsContext,
        size: CGSize,
        scene: CompactingDogAnimation.SceneState,
        stage: CompactingDogAnimation.Stage? = nil,
        dotColor: Color
    ) {
        let dotSpacing: CGFloat = 6
        let phase = CGFloat(scene.offset).truncatingRemainder(dividingBy: dotSpacing)
        var x = -phase
        while x < size.width {
            let lift = stage.map {
                CompactingDogAnimation.elevation(stage: $0, worldX: Double(x) + scene.offset)
            } ?? 0
            context.fill(
                Path(CGRect(x: x, y: Self.groundY + 2 - CGFloat(lift), width: 2, height: 2)),
                with: .color(dotColor)
            )
            x += dotSpacing
        }
    }

    /// 水中で犬が浮かぶ高さ（pt）。
    private static let swimLift: CGFloat = 12

    /// 犬を「奥の装備 → 本体 → 手前の装備 → 表情」の順で合成して描く。
    /// acquiring はイベント2で獲得しつつある装備（点滅で出現する獲得演出）。
    /// groundLift は犬の足元の地形の高さ。brandishesSword のとき背負い剣を
    /// 前方に構え替える。
    private func drawDog(
        context: GraphicsContext,
        scene: CompactingDogAnimation.SceneState,
        equipment: [CompactingDogAnimation.Equipment],
        acquiring: CompactingDogAnimation.Equipment? = nil,
        groundLift: CGFloat = 0,
        brandishesSword: Bool = false
    ) {
        let frame = scene.isSwimming
            ? CompactingDogSprites.dogSwimFrames[scene.runFrame]
            : CompactingDogSprites.dogFrames[scene.runFrame]
        // イベント1（戦闘など）中は拍ごとに小さく踏み込む。
        let lunge: CGFloat = scene.phase == .event1 && scene.effectFrame == 1 ? 6 : 0
        let leftX = CGFloat(CompactingDogAnimation.dogScreenX) + lunge
        let floatLift: CGFloat = scene.isSwimming ? Self.swimLift - CGFloat(scene.swimBob) : 0
        let bottomY = Self.groundY - groundLift - floatLift
            - CGFloat(scene.jumpHeight) * Self.jumpPixels

        var visible = equipment
        if let acquiring, scene.effectFrame == 1 {
            visible.append(acquiring)
        }
        if brandishesSword {
            visible.removeAll { $0 == .sword }
        }
        let overlays = visible.map(CompactingDogSprites.equipmentOverlay)
        for (overlay, behind) in overlays where behind {
            drawDogOverlay(overlay, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        }
        drawSprite(frame, bottomLeftX: leftX, bottomY: bottomY, context: context)
        for (overlay, behind) in overlays where !behind {
            drawDogOverlay(overlay, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        }
        if brandishesSword {
            drawDogOverlay(CompactingDogSprites.brandishedSword, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        }
        if scene.isSwimming, scene.effectFrame == 1 {
            drawDogOverlay(CompactingDogSprites.swimBubbles, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        }

        switch scene.emotion {
        case .relaxed:
            break
        case .joyful:
            drawDogOverlay(CompactingDogSprites.happyEyes, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        case .angry:
            drawDogOverlay(CompactingDogSprites.angryBrows, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        case .startled:
            drawDogOverlay(CompactingDogSprites.sweatDrop, dogLeftX: leftX, dogBottomY: bottomY, context: context)
        }
    }

    /// 犬スプライトのピクセル座標系のオーバーレイを、犬の描画位置に合わせて描く。
    private func drawDogOverlay(
        _ overlay: CompactingDogSprites.DogOverlay,
        dogLeftX: CGFloat,
        dogBottomY: CGFloat,
        context: GraphicsContext
    ) {
        let pixel = Self.pixelSize
        let dogTopY = dogBottomY - CGFloat(CompactingDogSprites.dogFrames[0].count) * pixel
        drawSprite(
            overlay.rows,
            bottomLeftX: dogLeftX + CGFloat(overlay.x) * pixel,
            bottomY: dogTopY + CGFloat(overlay.y + overlay.rows.count) * pixel,
            context: context
        )
    }

    private func drawEffects(
        context: GraphicsContext,
        scene: CompactingDogAnimation.SceneState,
        script: CompactingDogAnimation.StageScript?
    ) {
        switch scene.phase {
        case .event1:
            guard let script else { break }
            drawEventEffect(kind: script.event1, context: context, scene: scene)
        case .event2:
            guard let script else { break }
            drawEventEffect(kind: script.event2, context: context, scene: scene)
        case .celebrating:
            let offsets: [(CGFloat, CGFloat)] = scene.effectFrame == 0
                ? [(4, -56), (46, -48)]
                : [(24, -62), (60, -54)]
            for (dx, dy) in offsets {
                drawSprite(CompactingDogSprites.star, bottomLeftX: CGFloat(CompactingDogAnimation.dogScreenX) + dx, bottomY: Self.groundY + dy, context: context)
            }
        case .running:
            break
        }
    }

    /// イベント種別ごとの演出: fight=星 / friend=ハート2つ / reward=星＋ハート。
    private func drawEventEffect(
        kind: CompactingDogAnimation.EventKind,
        context: GraphicsContext,
        scene: CompactingDogAnimation.SceneState
    ) {
        let dogFrontX = CGFloat(CompactingDogAnimation.dogScreenX) + 66
        switch kind {
        case .fight:
            let offsets: [(CGFloat, CGFloat)] = scene.effectFrame == 0
                ? [(0, -30), (14, -14)]
                : [(-6, -20), (10, -36)]
            for (dx, dy) in offsets {
                drawSprite(CompactingDogSprites.star, bottomLeftX: dogFrontX + dx, bottomY: Self.groundY + dy, context: context)
            }
        case .friend:
            // 犬と相手の頭上にハートを点滅。
            let dogDx: CGFloat = scene.effectFrame == 0 ? 20 : 28
            drawSprite(CompactingDogSprites.heart, bottomLeftX: CGFloat(CompactingDogAnimation.dogScreenX) + dogDx, bottomY: Self.groundY - 56, context: context)
            drawSprite(CompactingDogSprites.heart, bottomLeftX: dogFrontX + 50, bottomY: Self.groundY - 48 - (scene.effectFrame == 0 ? 0 : 6), context: context)
        case .reward:
            let sparkleDx: CGFloat = scene.effectFrame == 0 ? 44 : 58
            drawSprite(CompactingDogSprites.star, bottomLeftX: dogFrontX + sparkleDx, bottomY: Self.groundY - 34 - (scene.effectFrame == 0 ? 0 : 8), context: context)
            drawSprite(CompactingDogSprites.heart, bottomLeftX: CGFloat(CompactingDogAnimation.dogScreenX) + 24, bottomY: Self.groundY - 56, context: context)
        }
    }
}
