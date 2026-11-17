import { LayoutSpec } from '../common/LayoutSpec'

/**
 * Compact official Select used by the conversion scope row.
 * Keeps the system dropdown (solid triangle, highlighted current option)
 * so additional consoles/formats only need more entries in `options`.
 */
@Component
export struct ScopeSelect {
  /** Localized role prefix, e.g. 机型 */
  @Prop label: string = ''
  /** Currently selected option value */
  @Prop value: string = ''
  options: string[] = []
  onSelect: (value: string) => void = () => {}


  private selectOptions(): SelectOption[] {
    const result: SelectOption[] = []
    for (const option of this.options) {
      result.push({ value: option })
    }
    return result
  }

  private selectedIndex(): number {
    const index = this.options.indexOf(this.value)
    return index < 0 ? 0 : index
  }

  build() {
    Select(this.selectOptions())
      .selected(this.selectedIndex())
      .value(this.value)
      .font({ size: 14, weight: FontWeight.Medium })
      .fontColor($r('app.color.text_primary'))
      .optionFont({ size: 14 })
      .optionFontColor($r('app.color.text_primary'))
      .selectedOptionFont({ size: 14, weight: FontWeight.Medium })
      .selectedOptionFontColor($r('app.color.accent'))
      .selectedOptionBgColor($r('app.color.accent_bg'))
      .height(40)
      .constraintSize({ minWidth: 84 })
      .backgroundColor($r('app.color.surface'))
      .borderRadius(LayoutSpec.controlRadius())
      .onSelect((index: number, value: string): void => {
        this.onSelect(value)
      })
      .accessibilityText(this.label + ' ' + this.value)
  }
}
