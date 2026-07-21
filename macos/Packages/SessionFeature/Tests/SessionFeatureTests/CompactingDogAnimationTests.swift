import Foundation
import Testing
@testable import SessionFeature

@Suite("CompactingDogAnimation: サイドスクロールのシーン導出")
struct CompactingDogAnimationTests {
    private let seaScript = CompactingDogAnimation.script(for: .sea)

    @Test func 区間導出は大周期で正規化され時計ずれは第1面の頭に接地する() {
        let grand = CompactingDogAnimation.grandPeriod

        #expect(CompactingDogAnimation.segment(elapsed: grand + 1.0)
            == CompactingDogAnimation.segment(elapsed: 1.0))
        #expect(CompactingDogAnimation.segment(elapsed: -0.5)
            == .stage(.sea, t: 0))
    }

    @Test func スクロール時間は停止イベント中に進まない() {
        let event1 = CompactingDogAnimation.event1Window

        let before = CompactingDogAnimation.scrollTime(at: event1.start)
        let during = CompactingDogAnimation.scrollTime(at: event1.start + event1.duration / 2)
        let after = CompactingDogAnimation.scrollTime(at: event1.start + event1.duration)

        #expect(before == during)
        #expect(during == after)
    }

    @Test func スクロール時間は停止イベントの外では実時間と同じ速度で進む() {
        let delta = CompactingDogAnimation.scrollTime(at: 2.0) - CompactingDogAnimation.scrollTime(at: 1.0)

        #expect(abs(delta - 1.0) < 0.0001)
    }

    @Test func ステージ終端のスクロール時間は全停止時間を除いた値になる() {
        let totalPause = CompactingDogAnimation.event1Window.duration
            + CompactingDogAnimation.event2Window.duration

        let tauEnd = CompactingDogAnimation.scrollTime(at: CompactingDogAnimation.stageDuration)

        #expect(abs(tauEnd - (CompactingDogAnimation.stageDuration - totalPause)) < 0.0001)
    }

    @Test func 各停止イベントで対応するフェーズになりステージ内にお祝いは無い() {
        #expect(CompactingDogAnimation.phase(at: 2.0) == .running)
        #expect(CompactingDogAnimation.phase(at: CompactingDogAnimation.event1Window.start + 0.5) == .event1)
        #expect(CompactingDogAnimation.phase(at: CompactingDogAnimation.event2Window.start + 0.5) == .event2)
        #expect(CompactingDogAnimation.phase(at: CompactingDogAnimation.stageDuration - 0.1) == .running)
    }

    @Test func 各ステージのジャンプ到着時刻に頂点が来る() {
        for stage in CompactingDogAnimation.Stage.allCases {
            let arrivals = CompactingDogAnimation.script(for: stage).jumpArrivals
            let halfWidth = CompactingDogAnimation.jumpHalfWidth(for: stage)
            for arrival in arrivals {
                #expect(CompactingDogAnimation.obstacleJumpHeight(
                    scrollTime: arrival, arrivals: arrivals, halfWidth: halfWidth
                ) > 0.99)
                #expect(CompactingDogAnimation.obstacleJumpHeight(
                    scrollTime: arrival + halfWidth + 0.01,
                    arrivals: arrivals,
                    halfWidth: halfWidth
                ) == 0)
            }
        }
    }

    @Test func 各ステージのジャンプは全て走行区間内に収まり窓が重ならない() {
        for stage in CompactingDogAnimation.Stage.allCases {
            let arrivals = CompactingDogAnimation.script(for: stage).jumpArrivals
            let halfWidth = CompactingDogAnimation.jumpHalfWidth(for: stage)
            for arrival in arrivals {
                #expect(arrival + halfWidth < CompactingDogAnimation.event1Window.start)
                #expect(arrival - halfWidth > 0)
            }
            for pair in zip(arrivals, arrivals.dropFirst()) {
                #expect(pair.1 - pair.0 >= halfWidth * 2)
            }
        }
    }

    @Test func 月は低重力で高くふわりと跳び走行中も弾む() {
        #expect(CompactingDogAnimation.jumpHalfWidth(for: .moon) > CompactingDogAnimation.jumpHalfWidth(for: .desert))
        #expect(CompactingDogAnimation.jumpBoost(for: .moon) > 1)

        // 障害物ジャンプの頂点は 1.25 倍
        let arrival = CompactingDogAnimation.script(for: .moon).jumpArrivals[0]
        let apex = CompactingDogAnimation.scene(at: arrival, stage: .moon)
        #expect(abs(apex.jumpHeight - 1.25) < 0.0001)

        // 障害物が無い走行区間でも低重力の弾みで足が浮く時刻がある
        let bounding = CompactingDogAnimation.scene(at: 0.55, stage: .moon)
        #expect(bounding.jumpHeight > 0.1)
        // 陸の通常ステージは障害物の外では接地
        #expect(CompactingDogAnimation.scene(at: 0.55, stage: .desert).jumpHeight == 0)
    }

    @Test func 障害物はジャンプ頂点で犬の中央の真下に来る() {
        let arrival = 1.8
        let offset = CompactingDogAnimation.scrollSpeed * arrival
        let obstacleScreenX = CompactingDogAnimation.obstacleWorldX(jumpArrival: arrival) - offset

        #expect(obstacleScreenX == CompactingDogAnimation.dogScreenX + 32)
    }

    @Test func イベント1の相手は開始時に犬の正面に居る() {
        let event1 = CompactingDogAnimation.event1Window
        let atEvent = CompactingDogAnimation.scene(at: event1.start + 0.1, stage: .sea)

        let actorScreenX = CompactingDogAnimation.actor1WorldX - atEvent.offset
        #expect(actorScreenX > CompactingDogAnimation.dogScreenX + 60)
        #expect(actorScreenX < 200)
    }

    @Test func 相手が去る台本ではイベント1後に消え残る台本では居続ける() {
        let afterEvent1 = CompactingDogAnimation.event1Window.start
            + CompactingDogAnimation.event1Window.duration + 0.1

        let seaScene = CompactingDogAnimation.scene(at: afterEvent1, stage: .sea)
        let iceScene = CompactingDogAnimation.scene(at: afterEvent1, stage: .ice)

        #expect(seaScene.actor1Visible == false)  // イルカは泳ぎ去る
        #expect(iceScene.actor1Visible)  // ペンギンは友達として残る
    }

    @Test func 各ステージの物語は差異を持つ() {
        let scripts = CompactingDogAnimation.Stage.allCases.map { CompactingDogAnimation.script(for: $0) }

        #expect(Set(scripts.map(\.jumpArrivals.count)).count >= 2)  // ジャンプ回数が一様でない
        #expect(scripts.contains { $0.event1 == .fight })
        #expect(scripts.contains { $0.event1 == .friend })
        #expect(scripts.contains { $0.event1 == .reward })
    }

    @Test func 停止イベント中は走りフレームが固定される() {
        let event1 = CompactingDogAnimation.scene(
            at: CompactingDogAnimation.event1Window.start + 0.1,
            stage: .river
        )

        #expect(event1.runFrame == 0)
    }

    @Test func ステージは圧縮開始時に先頭から始まり連続的に進み最後にゴール区間が来て周回する() {
        let stageLen = CompactingDogAnimation.stageDuration
        let stageCount = CompactingDogAnimation.Stage.allCases.count
        var seen: [CompactingDogAnimation.Stage] = []
        for index in 0..<stageCount {
            let segment = CompactingDogAnimation.segment(elapsed: Double(index) * stageLen + 1.0)
            guard case .stage(let stage, _) = segment else {
                Issue.record("ステージ区間のはずが \(segment)")
                continue
            }
            seen.append(stage)
        }

        #expect(seen == CompactingDogAnimation.Stage.allCases)  // 開始は第1面・順に連続遷移

        let goalElapsed = stageLen * Double(stageCount) + 0.5
        #expect(CompactingDogAnimation.segment(elapsed: goalElapsed) == .goal(t: 0.5))

        let wrapped = CompactingDogAnimation.segment(
            elapsed: CompactingDogAnimation.grandPeriod + 1.0
        )
        #expect(wrapped == .stage(.sea, t: 1.0))  // ゴール後は第1面へ周回
    }

    @Test func ゴール区間は旗が犬の正面に到着した時にお祝いへ入りスクロールが止まる() {
        let arrival = CompactingDogAnimation.goalRunIn
        let atArrival = CompactingDogAnimation.goalScene(at: arrival + 0.1)
        let midCelebrate = CompactingDogAnimation.goalScene(
            at: arrival + CompactingDogAnimation.goalCelebrate / 2
        )
        let running = CompactingDogAnimation.goalScene(at: 0.5)

        // 旗の到着位置 = 犬の正面（screen 112pt）
        let flagScreenX = CompactingDogAnimation.goalFlagWorldX
            - CompactingDogAnimation.scrollSpeed * arrival
        #expect(abs(flagScreenX - (CompactingDogAnimation.dogScreenX + 72)) < 0.0001)

        #expect(running.phase == .running)
        #expect(atArrival.phase == .celebrating)
        #expect(atArrival.offset == midCelebrate.offset)  // お祝い中はスクロール停止
        #expect(midCelebrate.jumpHeight >= 0)
        #expect(CompactingDogAnimation.goalScene(
            at: arrival + CompactingDogAnimation.goalCelebrate + 0.1
        ).phase == .running)  // お祝い後は走り出す
    }

    @Test func 表情は場面に応じて喜怒哀楽を切り替える() {
        let desertScript = CompactingDogAnimation.script(for: .desert)
        let event1Start = CompactingDogAnimation.event1Window.start

        // 楽: 走行中はすまし顔
        #expect(CompactingDogAnimation.scene(at: 2.0, stage: .desert).emotion == .relaxed)
        // 哀: 戦闘の出会い頭は驚き
        #expect(CompactingDogAnimation.emotion(at: event1Start + 0.2, script: desertScript) == .startled)
        // 怒: 驚きの後は怒って立ち向かう
        #expect(CompactingDogAnimation.emotion(
            at: event1Start + CompactingDogAnimation.fightStartleDuration + 0.1,
            script: desertScript
        ) == .angry)
        // 喜: 友達イベント（海のイルカ）とゴールのお祝い
        #expect(CompactingDogAnimation.emotion(at: event1Start + 0.2, script: seaScript) == .joyful)
        #expect(CompactingDogAnimation.goalScene(
            at: CompactingDogAnimation.goalRunIn + 0.1
        ).emotion == .joyful)
    }

    @Test func 装備はステージのイベント2クリアごとに1つずつ増えていく() {
        let afterEvent2 = CompactingDogAnimation.event2Window.start
            + CompactingDogAnimation.event2Window.duration + 0.1

        #expect(CompactingDogAnimation.ownedEquipment(stage: .sea, t: 1.0).isEmpty)  // 旅立ちは丸腰
        #expect(CompactingDogAnimation.ownedEquipment(stage: .sea, t: afterEvent2) == [.strawHat])
        // 火山到達時は剣まで所持（＝ドラゴン戦で構えられる）
        #expect(CompactingDogAnimation.ownedEquipment(stage: .volcano, t: 1.0)
            == [.strawHat, .flask, .sword])
        // 砂漠のサソリ戦（イベント1）の時点では剣は未入手＝素手で戦う
        #expect(!CompactingDogAnimation.ownedEquipment(
            stage: .desert,
            t: CompactingDogAnimation.event1Window.start + 0.1
        ).contains(.sword))
        // 氷山クリアで宇宙ヘルメット（次の月で身を守る）まで
        #expect(CompactingDogAnimation.ownedEquipment(stage: .ice, t: afterEvent2)
            == [.strawHat, .flask, .sword, .scarf, .helmet])
        #expect(CompactingDogAnimation.ownedEquipment(stage: .moon, t: afterEvent2)
            == CompactingDogAnimation.Equipment.allCases)  // 全ステージクリアで全装備
    }

    @Test func 獲得演出はイベント2の間だけそのステージの報酬を返す() {
        let midEvent2 = CompactingDogAnimation.event2Window.start + 0.5

        #expect(CompactingDogAnimation.acquiringEquipment(stage: .desert, t: midEvent2) == .sword)
        #expect(CompactingDogAnimation.acquiringEquipment(stage: .desert, t: 1.0) == nil)
        #expect(CompactingDogAnimation.acquiringEquipment(
            stage: .desert,
            t: CompactingDogAnimation.event2Window.start + CompactingDogAnimation.event2Window.duration + 0.1
        ) == nil)
    }

    @Test func ステージ報酬は全ステージで全装備を一巡する() {
        let rewards = CompactingDogAnimation.Stage.allCases.map(CompactingDogAnimation.stageReward)

        #expect(rewards == CompactingDogAnimation.Equipment.allCases)
    }

    @Test func 海だけが水中で犬掻きの揺れを持ち陸のステージは揺れない() {
        let seaScene = CompactingDogAnimation.scene(at: 0.4, stage: .sea)
        let riverScene = CompactingDogAnimation.scene(at: 0.4, stage: .river)

        #expect(seaScene.isSwimming)
        #expect(abs(seaScene.swimBob) > 0.1)  // t=0.4 は揺れの頂点（sin(π/2)）
        #expect(!riverScene.isSwimming)
        #expect(riverScene.swimBob == 0)
    }

    @Test func 水中では停止イベント中も掻き続ける() {
        let event1 = CompactingDogAnimation.scene(
            at: CompactingDogAnimation.event1Window.start
                + 1.0 / 6.0 + 0.01,  // 走りフレームが1になる時刻
            stage: .sea
        )

        #expect(event1.runFrame == 1)  // 陸なら 0 固定（停止）だが水中は掻き続ける
    }

    @Test func 上昇気泡は時間とともに上りスパン内で巻き戻る() {
        let span = 96.0

        let early = CompactingDogAnimation.risingBubbleAscent(elapsed: 1.0, index: 0, span: span)
        let later = CompactingDogAnimation.risingBubbleAscent(elapsed: 2.0, index: 0, span: span)
        let wrapped = CompactingDogAnimation.risingBubbleAscent(elapsed: span / 16.0 + 1.0, index: 0, span: span)

        #expect(later > early)  // 上昇する（速度 16pt/s）
        #expect(abs(wrapped - early) < 0.0001)  // スパンで巻き戻る
        for index in 0..<6 {
            let ascent = CompactingDogAnimation.risingBubbleAscent(elapsed: 3.0, index: index, span: span)
            #expect(ascent >= 0 && ascent < span)
        }
    }

    @Test func 犬掻きフレームは4本の脚を交互に伸ばす() {
        for frame in CompactingDogSprites.dogSwimFrames {
            #expect(frame[17].components(separatedBy: "LWL").count - 1 == 4)  // 4本の脚
        }
        // 交互: 伸びる脚の位置がフレーム間で異なる
        #expect(CompactingDogSprites.dogSwimFrames[0][18]
            != CompactingDogSprites.dogSwimFrames[1][18])
    }

    @Test func 火山の地形は登坂から山頂の平場を経て下山し麓は平地に戻る() {
        let hill = CompactingDogAnimation.hills(for: .volcano)[0]

        #expect(CompactingDogAnimation.elevation(stage: .volcano, worldX: hill.footStart) == 0)
        let midClimb = CompactingDogAnimation.elevation(
            stage: .volcano,
            worldX: (hill.footStart + hill.topStart) / 2
        )
        #expect(midClimb > 0 && midClimb < hill.height)
        // 山頂の平場にドラゴン（actor1）と温泉（actor2）が乗る
        #expect(CompactingDogAnimation.elevation(
            stage: .volcano, worldX: CompactingDogAnimation.actor1WorldX
        ) == hill.height)
        #expect(CompactingDogAnimation.elevation(
            stage: .volcano, worldX: CompactingDogAnimation.actor2WorldX
        ) == hill.height)
        #expect(CompactingDogAnimation.elevation(stage: .volcano, worldX: hill.footEnd + 1) == 0)
    }

    @Test func 地形の丘は各ステージのジャンプ障害物の位置と重ならない() {
        for stage in CompactingDogAnimation.Stage.allCases {
            let obstacleXs = CompactingDogAnimation.script(for: stage).jumpArrivals
                .map(CompactingDogAnimation.obstacleWorldX)
            for x in obstacleXs {
                #expect(CompactingDogAnimation.elevation(stage: stage, worldX: x) == 0)
            }
        }
    }

    @Test func スプライトの各フレームは行ごとの幅が揃っている() {
        let sprites = CompactingDogSprites.dogFrames + CompactingDogSprites.dogSwimFrames
            + CompactingDogSprites.scorpionFrames + CompactingDogSprites.dragonFrames
            + CompactingDogSprites.greyFrames
            + [
                CompactingDogSprites.ufo,
                CompactingDogSprites.moonCrater,
                CompactingDogSprites.moonCraterSmall,
                CompactingDogSprites.starTwinkle,
                CompactingDogSprites.earth,
                CompactingDogSprites.cactus,
                CompactingDogSprites.coral,
                CompactingDogSprites.rock,
                CompactingDogSprites.lavaRock,
                CompactingDogSprites.iceSpike,
                CompactingDogSprites.star,
                CompactingDogSprites.heart,
                CompactingDogSprites.flag,
                CompactingDogSprites.cloud,
                CompactingDogSprites.bubble,
                CompactingDogSprites.ember,
                CompactingDogSprites.snowflake,
                CompactingDogSprites.dolphin,
                CompactingDogSprites.treasureChest,
                CompactingDogSprites.fish,
                CompactingDogSprites.frog,
                CompactingDogSprites.oasis,
                CompactingDogSprites.hotSpring,
                CompactingDogSprites.penguin,
                CompactingDogSprites.igloo,
                CompactingDogSprites.happyEyes.rows,
                CompactingDogSprites.angryBrows.rows,
                CompactingDogSprites.sweatDrop.rows,
                CompactingDogSprites.swimBubbles.rows,
                CompactingDogSprites.brandishedSword.rows,
            ]
            + CompactingDogAnimation.Equipment.allCases.map {
                CompactingDogSprites.equipmentOverlay($0).overlay.rows
            }
        for sprite in sprites {
            let widths = Set(sprite.map(\.count))
            #expect(widths.count == 1)
        }
    }
}
