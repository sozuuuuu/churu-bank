import { Controller } from "@hotwired/stimulus"

// Turbo Frame の中身など、レイアウトを通らない所からねこのセリフを変える（Ui::ThemeHelper#cat_say_tag）。
// つながったら cat:say を投げ、消えたら cat:reset でページのセリフに戻す（例: 振込の確認画面 → びっくり、戻る → ふつう）
export default class extends Controller {
  static values = { text: String, face: { type: String, default: "normal" }, bounce: Boolean }

  connect() {
    window.dispatchEvent(new CustomEvent("cat:say", { detail: { text: this.textValue, face: this.faceValue, bounce: this.bounceValue } }))
  }

  disconnect() {
    window.dispatchEvent(new CustomEvent("cat:reset"))
  }
}
