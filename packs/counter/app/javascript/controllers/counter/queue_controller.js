import { Controller } from "@hotwired/stimulus"
import consumer from "controllers/counter/consumer"

// 行員の窓口の列（packs/counter_admin）。Counter::QueueChannel を購読する。
//   changed … 列が変わった（札を取った・返した・呼んだ・終わった）。列の Frame を読み直す
// 購読しているあいだは「窓口に行員がいる」として数えられ、待っている利用者の画面に出る
export default class extends Controller {
  static targets = ["frame"]

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "Counter::QueueChannel" },
      { received: (data) => data.type === "changed" && this.#reload() }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  #reload() {
    if (!this.hasFrameTarget) return
    const frame = this.frameTarget
    if (frame.src) frame.reload()
    else frame.src = frame.dataset.url
  }
}
