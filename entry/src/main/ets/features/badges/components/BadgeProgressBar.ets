// L4 Feature - Badges - Component
import type { BadgeProgress } from '../service/BadgesService';

@Component
export struct BadgeProgressBar {
  progress: BadgeProgress = { badgeId: '', current: 0, target: 1, percent: 0 };

  build() {
    Column({ space: 4 }) {
      Row() {
        Text(`${this.progress.current}`)
          .fontSize(12)
          .fontColor('#666666')
        Blank()
        Text(`${this.progress.target}`)
          .fontSize(12)
          .fontColor('#666666')
      }
      .width('100%')

      Stack({ alignContent: Alignment.Start }) {
        Rect()
          .width('100%')
          .height(6)
          .fill('#E5E5E5')
          .radius(3)

        Rect()
          .width(`${Math.min(this.progress.percent, 100)}%`)
          .height(6)
          .fill('#F4A261')
          .radius(3)
      }
      .width('100%')
    }
    .width('100%')
  }
}
