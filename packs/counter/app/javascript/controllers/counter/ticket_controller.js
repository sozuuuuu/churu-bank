import { Controller } from "@hotwired/stimulus"
import consumer from "controllers/counter/consumer"

// 利用者の番号札（packs/counter の counter/tickets/_waiting）。Counter::TicketChannel を購読して:
//   position … 「前に何人」と、窓口に行員がいるかを書き換える
//   called   … ねこが「5 番の方、窓口へどうぞにゃ」（うれしい顔で弾む）。Frame を読み直してチャットにする
//   closed   … Frame を読み直す（札を返した・終わった）
export default class extends Controller {
  static targets = ["ahead", "staff", "staffText"]
  static values = { ticketId: Number, number: Number }

  connect() {
    this.subscription = consumer.subscriptions.create(
      { channel: "Counter::TicketChannel", ticket_id: this.ticketIdValue },
      { received: (data) => this.#received(data) }
    )
  }

  disconnect() {
    this.subscription?.unsubscribe()
  }

  #received(data) {
    switch (data.type) {
      case "position": return this.#position(data)
      case "called": return this.#called(data)
      case "closed": return this.#reloadFrame()
    }
  }

  #position({ ahead, staff_at_counter: atCounter }) {
    const before = this.ahead
    this.ahead = ahead
    this.aheadTarget.textContent = ahead === 0 ? "次があなたの番です" : `前に ${ahead} 人`
    this.staffTarget.classList.toggle("is-present", atCounter)
    this.staffTextTarget.textContent = atCounter ? "窓口に行員がいます" : "いま窓口に行員がいません（もうすこしお待ちください）"

    // 順番が進んだときだけ、ねこがひとこと（ページを開いた直後の1回目は黙っている）
    if (before !== undefined && ahead < before) {
      const text = ahead === 0 ? "次が呼ばれる番にゃ！ もうすぐにゃ。" : `順番が進んだにゃ。前にあと ${ahead} 人にゃ。`
      this.#say({ text, face: "normal" })
    }
  }

  #called({ number, staff_name: staffName }) {
    this.#say({ text: `${number} 番の方、窓口へどうぞにゃ！ ${staffName}さんがお待ちしてるにゃ。`, face: "happy", bounce: true })
    this.#reloadFrame()
  }

  #say(detail) {
    window.dispatchEvent(new CustomEvent("cat:say", { detail }))
  }

  // この札の Frame（counter_ticket）だけを読み直す。セリフ窓はそのまま
  #reloadFrame() {
    const frame = this.element.closest("turbo-frame")
    if (!frame) return
    if (frame.src) frame.reload()
    else frame.src = window.location.href
  }
}
