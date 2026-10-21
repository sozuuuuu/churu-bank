import { Controller } from "@hotwired/stimulus"

// 口座ページの出来事の演出。arrival:arrived / transfer-status:settled を受けて、
//   - ねこのセリフ窓に cat:say（表情とセリフ。うれしいときは弾んでキラッ）
//   - 振込完了なら「振込完了！」の画面（dialog.hooray。集中線・はんこ）を開く
// 動きは CSS とセリフ窓（serif）の側で「視差効果を減らす」設定なら止まる。外部ライブラリは使わない
export default class extends Controller {
  static targets = ["hooray", "hoorayTo", "hoorayAmount", "hoorayMeta", "hooraySerif"]

  burst({ detail: { text, face, bounce, hooray } }) {
    window.dispatchEvent(new CustomEvent("cat:say", { detail: { text, face, bounce } }))
    if (hooray && this.hasHoorayTarget) this.#openHooray(hooray, text)
  }

  #openHooray({ to, amount, meta }, text) {
    const dialog = this.hoorayTarget
    this.hoorayToTarget.textContent = `${to} へ`
    this.hoorayAmountTarget.textContent = amount.toLocaleString("ja-JP")
    this.hoorayMetaTarget.textContent = meta
    this.hooraySerifTarget.dataset.serifTextValue = text
    if (dialog.open) dialog.close()
    dialog.showModal()
  }
}
