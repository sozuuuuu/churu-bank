import { Controller } from "@hotwired/stimulus"

// 金額欄に +10 / +50 … を足していくボタン
export default class extends Controller {
  static targets = ["input"]

  add({ params: { value } }) {
    const current = parseInt(this.inputTarget.value, 10) || 0
    this.inputTarget.value = current + value
    this.inputTarget.focus()
  }

  clear() {
    this.inputTarget.value = ""
    this.inputTarget.focus()
  }
}
