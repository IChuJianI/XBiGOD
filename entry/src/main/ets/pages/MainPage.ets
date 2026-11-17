import { picker, fileIo, Environment, fileUri } from '@kit.CoreFileKit'
import { common, abilityAccessCtrl, bundleManager } from '@kit.AbilityKit'
import { mediaquery, uiMaterial, SymbolGlyphModifier, promptAction } from '@kit.ArkUI'
import { deviceInfo, pasteboard } from '@kit.BasicServicesKit'
import { ConversionTask, TaskDirection, TaskStatus } from '../model/ConversionTask'
import { ProgressStage } from '../model/ConversionState'
import { HistoryKind, HistoryRecord } from '../model/HistoryRecord'
import { HistoryStore } from '../model/HistoryStore'
import { MODE_DARK, MODE_LIGHT, MODE_SYSTEM, ThemeStore } from '../model/ThemeStore'
import { LANG_EN, LANG_JA, LANG_SYSTEM, LANG_ZH, LANG_ZH_HANT, LanguageStore } from '../model/LanguageStore'
import { GLOW_CLEAR, GLOW_SOFT, GLOW_STANDARD, GlowStore } from '../model/GlowStore'
import { StatusCard } from '../components/StatusCard'
import { ScopeSelect } from '../components/ScopeSelect'
import { GameCover } from '../components/GameCover'
import { ActionButtons } from '../components/ActionButtons'
import { TaskListItem } from '../components/TaskListItem'
import { SideNav } from '../components/SideNav'
import { SettingsView } from '../components/SettingsView'
import { AboutView } from '../components/AboutView'
import { ColorModeView } from '../components/ColorModeView'
import { LanguageView } from '../components/LanguageView'
import { GlowView } from '../components/GlowView'
import { LicensesPage } from '../components/LicensesPage'
import { LayoutSpec } from '../common/LayoutSpec'
import { TabIndex } from '../common/TabIndex'
import xbigod from 'libxbigod_napi.so'
import { IsoInfoResult, IconResult, GodInfoResult } from 'libxbigod_napi.so'

interface NativeFailure {
  code?: string
  detail?: string
}

const ROUTE_MAIN: string = 'main'

const CONSOLE_OPTIONS: string[] = ['Xbox 360']
const FORMAT_ISO_TO_GOD: string = 'ISO - GOD'
const FORMAT_GOD_TO_ISO: string = 'GOD - ISO'
const FORMAT_OPTIONS: string[] = [FORMAT_ISO_TO_GOD, FORMAT_GOD_TO_ISO]

const PANEL_NONE: number = 0
const PANEL_HISTORY: number = 1
const PANEL_SETTINGS: number = 2
const PANEL_ABOUT: number = 3
const PANEL_THEME: number = 4
const PANEL_LICENSES: number = 5
const PANEL_GLOW: number = 6
const PANEL_LANGUAGE: number = 7

const GOD_STAGE_READING_PARTS: number = 0
const GOD_STAGE_WRITING_HEADER: number = 1
const GOD_STAGE_FIXING_OFFSETS: number = 2

const GOD_FOLDER_MAX_DEPTH: number = 5
const GOD_FOLDER_MAX_DIRS: number = 500
const GOD_FOLDER_MAX_RESULTS: number = 50
const GOD_FOLDER_SCAN_BATCH: number = 8

@Entry
@Component
struct MainPage {
  @State statusText: string = ''
  @State selectedDevice: string = 'Xbox 360'
  @State selectedFormat: string = 'ISO - GOD'
  @State tasks: ConversionTask[] = []
  @State queueRunning: boolean = false
  @State cancelling: boolean = false
  @State currentTab: number = TabIndex.HOME
  @State isWidth600: boolean = false
  @State isWidth840: boolean = false
  @State historyRecords: HistoryRecord[] = []
  @State historyKind: HistoryKind = HistoryKind.CONVERT
  @State historyFilter: string = ''
  @State colorMode: number = MODE_SYSTEM
  @State language: number = LANG_SYSTEM
  @State glowLevel: number = GLOW_STANDARD
  @State appVersion: string = ''
  @State appBundleName: string = ''
  @State subPageActive: boolean = false
  @State panelOpen: boolean = false
  @State panelKind: number = PANEL_NONE
  @State aboutFromSettings: boolean = false
  private viewWidth: number = 0
  private viewHeight: number = 0
  private isPc: boolean = false
  private isPhone: boolean = true
  private godPicking: boolean = false
  private width600Listener: mediaquery.MediaQueryListener | undefined = undefined
  private width840Listener: mediaquery.MediaQueryListener | undefined = undefined
  private historyStore: HistoryStore = new HistoryStore()
  private mobileStack: NavPathStack = new NavPathStack()
  private desktopStack: NavPathStack = new NavPathStack()
  private websiteUrl: string = 'www.52wfun.com'
  private emailAddress: string = '3093376617@qq.com'
  private nextTaskId: number = 1
  private currentTaskId: number = -1
  private iconJobs: Map<number, Promise<void>> = new Map()
  private queueCancelled: boolean = false
  private autoContinue: boolean = true
  private downloadDir: string = ''

  private str(res: Resource): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    return context.resourceManager.getStringSync(res.id)
  }

  aboutToAppear(): void {
    this.statusText = this.str($r('app.string.status_select_iso'))
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    this.historyStore.init(context)
    this.historyRecords = this.historyStore.getAll()
    this.colorMode = ThemeStore.load(context)
    this.language = LanguageStore.load(context)
    this.glowLevel = GlowStore.load(context)
    this.isPc = deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_2IN1
    this.isPhone = deviceInfo.deviceType === deviceInfo.DeviceTypes.TYPE_PHONE
    this.loadAppInfo()

    const mediaQuery = this.getUIContext().getMediaQuery()
    const medium = mediaQuery.matchMediaSync('(width>=600vp)')
    this.isWidth600 = medium.matches
    this.width600Listener = medium
    medium.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isWidth600 = result.matches
    })

    const large = mediaQuery.matchMediaSync('(width>=840vp)')
    this.isWidth840 = large.matches
    this.width840Listener = large
    large.on('change', (result: mediaquery.MediaQueryResult) => {
      this.isWidth840 = result.matches
      this.syncShellStacks()
    })

    this.syncShellStacks()
  }

  aboutToDisappear(): void {
    this.closeAllTaskFiles()
    if (this.width600Listener !== undefined) {
      this.width600Listener.off('change')
      this.width600Listener = undefined
    }
    if (this.width840Listener !== undefined) {
      this.width840Listener.off('change')
      this.width840Listener = undefined
    }
  }

  onBackPress(): boolean {
    if (this.panelOpen) {
      return false
    }
    if (this.activeStack().size() > 0) {
      return false
    }
    if (!this.isSidebarLayout() && this.currentTab !== TabIndex.HOME) {
      this.selectTab(TabIndex.HOME)
      return true
    }
    return false
  }

  private closeAllTaskFiles(): void {
    for (const task of this.tasks) {
      task.closeFile()
    }
  }

  private activeStack(): NavPathStack {
    return this.isSidebarLayout() ? this.desktopStack : this.mobileStack
  }

  private sameRoutes(a: string[], b: string[]): boolean {
    if (a.length !== b.length) {
      return false
    }
    for (let i = 0; i < a.length; i++) {
      if (a[i] !== b[i]) {
        return false
      }
    }
    return true
  }

  /** 两套外壳各有自己的栈：跨 840vp 时把当前可见路由搬到目标栈 */
  private syncShellStacks(): void {
    if (this.isSidebarLayout()) {
      const names: string[] = this.mobileStack.getAllPathName()
      const target: string[] = [ROUTE_MAIN]
      for (let i = 0; i < names.length; i++) {
        if (names[i] !== ROUTE_MAIN) {
          target.push(names[i])
        }
      }
      if (!this.sameRoutes(this.desktopStack.getAllPathName(), target)) {
        this.desktopStack.clear()
        for (let i = 0; i < target.length; i++) {
          this.desktopStack.pushPath(new NavPathInfo(target[i], null))
        }
      }
      this.mobileStack.clear()
      return
    }
    const names: string[] = this.desktopStack.getAllPathName()
    const target: string[] = []
    for (let i = 0; i < names.length; i++) {
      if (names[i] !== ROUTE_MAIN) {
        target.push(names[i])
      }
    }
    if (!this.sameRoutes(this.mobileStack.getAllPathName(), target)) {
      this.mobileStack.clear()
      for (let i = 0; i < target.length; i++) {
        this.mobileStack.pushPath(new NavPathInfo(target[i], null))
      }
    }
    this.desktopStack.clear()
    this.subPageActive = false
  }

  /** 侧栏“关于”是固定入口：直接以半模态面板打开 */
  private openAbout(): void {
    this.openPanel(PANEL_ABOUT)
  }

  private openPanel(kind: number): void {
    this.panelKind = kind
    this.aboutFromSettings = false
    this.panelOpen = true
  }

  private switchDesktopTab(index: number): void {
    this.currentTab = index
    this.subPageActive = false
    if (this.desktopStack.size() === 0) {
      this.desktopStack.pushPath(new NavPathInfo(ROUTE_MAIN, null))
    } else if (this.desktopStack.size() > 1) {
      this.desktopStack.popToIndex(0)
    }
  }

  private titleOptions(): NavigationTitleOptions {
    return {
      barStyle: BarStyle.STANDARD,
      backgroundColor: $r('app.color.surface'),
      systemMaterial: new uiMaterial.ImmersiveMaterial({
        style: GlowStore.titleStyle(this.glowLevel),
        interactive: true,
        lightEffect: {}
      })
    }
  }

  private historyMenu(): NavigationMenuItem {
    return {
      value: this.str($r('app.string.tab_history')),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.clock'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')]),
      action: (): void => this.openPanel(PANEL_HISTORY)
    }
  }

  private settingsMenu(): NavigationMenuItem {
    return {
      value: this.str($r('app.string.tab_settings')),
      symbolIcon: new SymbolGlyphModifier($r('sys.symbol.gearshape'))
        .fontSize(22)
        .fontColor([$r('app.color.text_primary')]),
      action: (): void => this.openPanel(PANEL_SETTINGS)
    }
  }

  /** 三端一致：历史与设置都在右上角 */
  private topMenus(): NavigationMenuItem[] {
    return [this.historyMenu(), this.settingsMenu()]
  }

  private loadAppInfo(): void {
    try {
      const info = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT)
      this.appVersion = info.versionName
      this.appBundleName = info.name
    } catch (_e) {
      // ignore
    }
  }

  build() {
    Stack() {
      if (this.isSidebarLayout()) {
        this.desktopShell()
      } else {
        this.mobileShell()
      }
    }
    .width('100%')
    .height('100%')
    .background($r('app.color.page_bg'))
    .onAreaChange((oldArea: Area, newArea: Area): void => {
      this.viewWidth = Number(newArea.width)
      this.viewHeight = Number(newArea.height)
    })
    .bindSheet($$this.panelOpen, this.panelBody(), this.panelOptions())
  }

  @Builder
  desktopShell() {
    Navigation(this.desktopStack) {
      SideNav({
        current: this.currentTab,
        subPageActive: this.subPageActive,
        aboutActive: this.panelOpen && this.panelKind === PANEL_ABOUT,
        onSelect: (index: number): void => this.switchDesktopTab(index),
        onOpenAbout: (): void => this.openAbout()
      })
    }
    .mode(NavigationMode.Split)
    .navBarWidth(LayoutSpec.SIDEBAR_WIDTH)
    .navBarWidthRange([260, 360])
    .hideTitleBar(true)
    .hideBackButton(true)
    .navDestination(this.pageMap)
    .divider({ color: $r('app.color.divider'), startMargin: 0, endMargin: 0 })
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  mobileShell() {
    Navigation(this.mobileStack) {
      this.compactTabs()
    }
    .mode(NavigationMode.Stack)
    .title(this.titleForTab(), this.titleOptions())
    .titleMode(NavigationTitleMode.Mini)
    .hideBackButton(true)
    .menus(this.topMenus())
    .navDestination(this.pageMap)
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.page_bg'))
  }

  @Builder
  pageMap(name: string) {
    if (name === ROUTE_MAIN) {
      this.mainPage()
    }
  }

  @Builder
  mainPage() {
    NavDestination() {
      Column() {
        if (this.currentTab === TabIndex.CONVERT) {
          this.converterContent()
        } else {
          this.homeContent()
        }
      }
      .width('100%')
      .height('100%')
    }
    .title(this.titleForTab(), this.titleOptions())
    .hideBackButton(true)
    .menus(this.topMenus())
    .backgroundColor($r('app.color.page_bg'))
    .onShown((): void => {
      this.subPageActive = false
    })
  }

  @Builder
  panelBody() {
    if (this.panelKind === PANEL_HISTORY) {
      Column() {
        this.historyContent()
      }
      .width('100%')
      .height('100%')
    } else if (this.panelKind === PANEL_SETTINGS) {
      SettingsView({
        languageLabel: this.languageLabel(),
        colorModeLabel: this.colorModeLabel(),
        glowLabel: this.glowLabel(),
        showAbout: !this.isSidebarLayout(),
        transparentBg: this.panelGlass(),
        onOpenLanguage: (): void => {
          this.panelKind = PANEL_LANGUAGE
        },
        onOpenTheme: (): void => {
          this.panelKind = PANEL_THEME
        },
        onOpenGlow: (): void => {
          this.panelKind = PANEL_GLOW
        },
        onOpenAbout: (): void => {
          this.aboutFromSettings = true
          this.panelKind = PANEL_ABOUT
        }
      })
    } else if (this.panelKind === PANEL_LANGUAGE) {
      Column() {
        this.panelBack($r('app.string.tab_settings'), PANEL_SETTINGS)
        Column() {
          LanguageView({
            language: this.language,
            transparentBg: this.panelGlass(),
            onSelect: (mode: number): void => this.setLanguage(mode)
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panelKind === PANEL_THEME) {
      Column() {
        this.panelBack($r('app.string.tab_settings'), PANEL_SETTINGS)
        Column() {
          ColorModeView({
            colorMode: this.colorMode,
            transparentBg: this.panelGlass(),
            onSelect: (mode: number): void => this.setColorMode(mode)
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panelKind === PANEL_GLOW) {
      Column() {
        this.panelBack($r('app.string.tab_settings'), PANEL_SETTINGS)
        Column() {
          GlowView({
            glowLevel: this.glowLevel,
            transparentBg: this.panelGlass(),
            onSelect: (level: number): void => this.setGlowLevel(level)
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panelKind === PANEL_ABOUT) {
      Column() {
        if (this.aboutFromSettings) {
          this.panelBack($r('app.string.tab_settings'), PANEL_SETTINGS)
        }
        Column() {
          AboutView({
            appVersion: this.appVersion,
            appBundleName: this.appBundleName,
            email: this.emailAddress,
            website: this.websiteUrl,
            transparentBg: this.panelGlass(),
            onOpenLicenses: (): void => {
              this.panelKind = PANEL_LICENSES
            },
            onCopyEmail: (): void => {
              this.copyText(this.emailAddress, $r('app.string.about_email_copied'))
            },
            onCopyWebsite: (): void => {
              this.copyText(this.websiteUrl, $r('app.string.about_website_copied'))
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    } else if (this.panelKind === PANEL_LICENSES) {
      Column() {
        this.panelBack($r('app.string.about_app_title'), PANEL_ABOUT)
        Column() {
          LicensesPage({
            pagePadding: this.pagePadding(),
            contentMaxWidth: this.contentMaxWidth(),
            bottomInset: this.pagePadding()
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  panelBack(label: Resource, kind: number) {
    Button({ type: ButtonType.Normal, stateEffect: true }) {
      Row({ space: 2 }) {
        SymbolGlyph($r('sys.symbol.chevron_left'))
          .fontSize(16)
          .fontColor([$r('app.color.accent')])
        Text(label)
          .fontSize(14)
          .fontColor($r('app.color.accent'))
      }
    }
    .height(40)
    .margin({ left: 8, top: 4 })
    .padding({ left: 8, right: 12 })
    .backgroundColor('#00000000')
    .borderRadius(8)
    .hoverEffect(HoverEffect.Highlight)
    .accessibilityText(this.str($r('app.string.action_back')) + ' ' + this.str(label))
    .onClick((): void => {
      this.panelKind = kind
    })
  }

  private panelOptions(): SheetOptions {
    const centered: boolean = this.centeredPanel()
    return {
      preferType: centered ? SheetType.CENTER : SheetType.BOTTOM,
      width: centered ? this.panelSheetWidth() : undefined,
      height: centered ? this.panelSheetHeight() : undefined,
      detents: centered ? undefined : [SheetSize.MEDIUM, SheetSize.LARGE],
      title: this.panelTitleOptions(),
      dragBar: !centered,
      showClose: true,
      backgroundColor: this.panelGlass() ? Color.Transparent : $r('app.color.page_bg'),
      systemMaterial: this.panelGlass() ? this.panelMaterial() : undefined,
      onWillDismiss: (action: DismissSheetAction): void => {
        if (action.reason === DismissReason.PRESS_BACK) {
          if (this.panelKind === PANEL_ABOUT && this.aboutFromSettings) {
            this.panelKind = PANEL_SETTINGS
            return
          }
          if (this.panelKind === PANEL_LANGUAGE) {
            this.panelKind = PANEL_SETTINGS
            return
          }
          if (this.panelKind === PANEL_THEME) {
            this.panelKind = PANEL_SETTINGS
            return
          }
          if (this.panelKind === PANEL_GLOW) {
            this.panelKind = PANEL_SETTINGS
            return
          }
          if (this.panelKind === PANEL_LICENSES) {
            this.panelKind = PANEL_ABOUT
            return
          }
        }
        action.dismiss()
      },
      onDisappear: (): void => {
        this.panelOpen = false
      }
    }
  }

  private panelTitleOptions(): SheetTitleOptions {
    let title: Resource = $r('app.string.tab_history')
    if (this.panelKind === PANEL_SETTINGS) {
      title = $r('app.string.tab_settings')
    } else if (this.panelKind === PANEL_LANGUAGE) {
      title = $r('app.string.settings_language')
    } else if (this.panelKind === PANEL_THEME) {
      title = $r('app.string.settings_dark_mode')
    } else if (this.panelKind === PANEL_GLOW) {
      title = $r('app.string.settings_glow')
    } else if (this.panelKind === PANEL_ABOUT) {
      title = $r('app.string.about_app_title')
    } else if (this.panelKind === PANEL_LICENSES) {
      title = $r('app.string.licenses_title')
    }
    const options: SheetTitleOptions = { title: this.str(title) }
    return options
  }

  /** 手机底部半模态，平板与电脑居中；按设备类型判断，不跟随窗口宽度 */
  private centeredPanel(): boolean {
    const type: string = deviceInfo.deviceType
    return type !== 'phone' && type !== 'wearable' && type !== 'car'
  }

  private panelSheetWidth(): number {
    if (this.viewWidth <= 0) {
      return 560
    }
    return Math.min(560, Math.max(320, this.viewWidth - 48))
  }

  private panelSheetHeight(): number {
    if (this.viewHeight <= 0) {
      return 640
    }
    return Math.min(640, Math.max(360, this.viewHeight - 64))
  }

  private panelGlass(): boolean {
    return uiMaterial.isImmersiveMaterialSupported()
  }

  private panelMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: GlowStore.barStyle(this.glowLevel)
    })
  }

  private isSidebarLayout(): boolean {
    return this.isPc && this.isWidth840
  }

  private pagePadding(): number {
    if (this.isPc) {
      return LayoutSpec.MARGIN_EXPANDED
    }
    return this.isWidth600 ? LayoutSpec.MARGIN_MEDIUM : LayoutSpec.MARGIN_COMPACT
  }

  private contentMaxWidth(): number {
    return this.isPc ? LayoutSpec.CONTENT_MAX_WIDTH_EXPANDED : LayoutSpec.CONTENT_MAX_WIDTH_COMPACT
  }

  private contentSpacing(): number {
    return this.isWidth600 ? LayoutSpec.SPACING_EXPANDED : LayoutSpec.SPACING_COMPACT
  }

  private bottomContentInset(): number {
    if (this.isSidebarLayout()) {
      return this.pagePadding()
    }
    return this.pagePadding() + LayoutSpec.COMPACT_BOTTOM_INSET
  }

  // 2.1.5.2.2: transition duration floor by device size (<8.5" 200ms, 8.5–12" 250ms, >12" 300ms).
  private transitionDurationMs(): number {
    return this.isPc ? 300 : 250
  }

  private selectTab(index: number): void {
    this.currentTab = index
  }

  private titleForTab(): string {
    if (this.currentTab === TabIndex.CONVERT) {
      return this.str($r('app.string.tab_convert'))
    }
    return this.str($r('app.string.tab_home'))
  }

  private openConverter(): void {
    if (this.isSidebarLayout()) {
      this.switchDesktopTab(TabIndex.CONVERT)
    } else {
      this.selectTab(TabIndex.CONVERT)
    }
  }

  // ── 首页：只做介绍与引导，不承载转换操作 ──────────────

  @Builder
  homeContent() {
    Scroll() {
      Column() {
        Column({ space: 20 }) {
          this.homeHero()

          Column({ space: 8 }) {
            Text($r('app.string.home_steps_title'))
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .width('100%')

            Column() {
              this.homeStep('1', $r('app.string.home_step_add_title'), $r('app.string.home_step_add_desc'))
              Divider()
                .strokeWidth(0.5)
                .color($r('app.color.divider'))
                .margin({ left: 56, right: 16 })
              this.homeStep('2', $r('app.string.home_step_convert_title'),
                $r('app.string.home_step_convert_desc'))
              Divider()
                .strokeWidth(0.5)
                .color($r('app.color.divider'))
                .margin({ left: 56, right: 16 })
              this.homeStep('3', $r('app.string.home_step_output_title'),
                $r('app.string.home_step_output_desc'))
            }
            .width('100%')
            .backgroundColor($r('app.color.surface'))
            .borderRadius(15)
          }
          .width('100%')

          Column({ space: 12 }) {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 8 }) {
                SymbolGlyph($r('sys.symbol.arrow_down_square'))
                  .fontSize(20)
                  .fontColor([Color.White])
                Text($r('app.string.action_open_converter'))
                  .fontSize(16)
                  .fontWeight(FontWeight.Medium)
                  .fontColor(Color.White)
              }
            }
            .width('100%')
            .height(48)
            .backgroundColor($r('app.color.success_btn'))
            .borderRadius(LayoutSpec.controlRadius())
            .onClick((): void => this.openConverter())

            Row({ space: 6 }) {
              SymbolGlyph($r('sys.symbol.checkmark_shield'))
                .fontSize(14)
                .fontColor([$r('app.color.text_secondary')])
              Text($r('app.string.home_local_note'))
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .padding({
        left: this.pagePadding(),
        right: this.pagePadding(),
        top: this.pagePadding(),
        bottom: this.bottomContentInset()
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  homeHero() {
    Column({ space: 12 }) {
      Image($r('app.media.startIcon'))
        .width(80)
        .height(80)
        .borderRadius(22)
        .clip(true)
      Column({ space: 6 }) {
        Text($r('app.string.app_name'))
          .fontSize(26)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
        Text($r('app.string.app_tagline'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .alignItems(HorizontalAlign.Center)
      Text($r('app.string.home_intro'))
        .fontSize(14)
        .lineHeight(22)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Center)
        .constraintSize({ maxWidth: 520 })
    }
    .width('100%')
    .padding({ top: 24, bottom: 8 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  homeStep(step: string, title: Resource, desc: Resource) {
    Row({ space: 12 }) {
      Stack() {
        Text(step)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.accent'))
      }
      .width(28)
      .height(28)
      .borderRadius(14)
      .backgroundColor($r('app.color.accent_bg'))
      .accessibilityLevel('no')

      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
        Text(desc)
          .fontSize(13)
          .lineHeight(18)
          .fontColor($r('app.color.text_secondary'))
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding({ top: 14, bottom: 14, left: 16, right: 16 })
    .alignItems(VerticalAlign.Top)
  }

  /** 分类胶囊独立于状态条目，宽屏放在条目左侧，窄屏放在条目上方 */
  @Builder
  scopeSelectors() {
    Row({ space: 6 }) {
      ScopeSelect({
        label: this.formatResource($r('app.string.convert_scope_device').id, []),
        value: this.selectedDevice,
        options: CONSOLE_OPTIONS,
        onSelect: (value: string): void => {
          this.selectedDevice = value
        }
      })
      ScopeSelect({
        label: this.formatResource($r('app.string.convert_scope_format').id, []),
        value: this.selectedFormat,
        options: FORMAT_OPTIONS,
        onSelect: (value: string): void => {
          this.selectedFormat = value
          this.setStatusForQueue()
        }
      })
    }
  }

  @Builder
  statusEntry() {
    StatusCard({
      statusText: this.statusText,
      isOk: this.allTasksCompleted(),
      isBusy: this.queueRunning,
      isError: !this.queueRunning && this.hasErrorTasks()
    })
  }

  @Builder
  converterContent() {
    Scroll() {
      Column() {
        Column({ space: this.contentSpacing() }) {
          if (this.isWidth600) {
            Row({ space: 12 }) {
              this.scopeSelectors()
              Row() {
                this.statusEntry()
              }
              .layoutWeight(1)
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          } else {
            Column({ space: 10 }) {
              this.scopeSelectors()
              this.statusEntry()
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          ActionButtons({
            onAddIso: (): void => this.handleAddClick(),
            onStartAll: () => this.confirmStartQueue(),
            canStartAll: this.hasReadyTasks(),
            isConverting: this.queueRunning,
            isGodMode: this.isGodMode()
          })

          this.queueSection()
        }
        .width('100%')
        .constraintSize({ maxWidth: this.contentMaxWidth() })
      }
      .width('100%')
      .padding({
        left: this.pagePadding(),
        right: this.pagePadding(),
        top: this.pagePadding(),
        bottom: this.bottomContentInset()
      })
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.Top)
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
  }

  @Builder
  queueSection() {
    Column({ space: 8 }) {
      Row() {
        Text($r('app.string.queue_title'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        if (this.tasks.length > 0) {
          Text(this.queueSummaryText())
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
        }
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      if (this.tasks.length === 0) {
        Column({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.arrow_down_square'))
            .fontSize(32)
            .fontColor([$r('app.color.icon_empty')])
          Text($r('app.string.queue_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding({ top: 32, bottom: 32, left: 16, right: 16 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius(15)
      } else {
        if (this.queueRunning) {
          Button({ type: ButtonType.Normal }) {
            Row() {
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(18)
                .fontColor([Color.White])
                .margin({ right: 8 })
              Text(this.cancelling
                ? $r('app.string.progress_cancelling')
                : $r('app.string.action_cancel_task'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(Color.White)
            }
          }
          .width('100%')
          .height(40)
          .backgroundColor($r('app.color.danger_btn'))
          .fontColor(Color.White)
          .borderRadius(LayoutSpec.controlRadius())
          .enabled(!this.cancelling)
          .onClick(() => {
            this.cancelCurrentTask()
          })
        }

        GridRow({
          columns: 2,
          gutter: { x: 8, y: 8 }
        }) {
          ForEach(this.tasks, (task: ConversionTask) => {
            GridCol({ span: this.isPhone ? 2 : 1 }) {
              TaskListItem({
                task: task,
                canStart: !this.queueRunning,
                unknownTitle: this.str(task.direction === TaskDirection.GOD_TO_ISO
                  ? $r('app.string.god_unknown_title')
                  : $r('app.string.task_unknown_title')),
                errorText: this.taskErrorText(task),
                onStart: () => {
                  this.confirmStartTask(task)
                },
                onRemove: () => {
                  this.confirmRemoveTask(task)
                },
                onCancel: () => {
                  this.cancelCurrentTask()
                }
              })
            }
          }, (task: ConversionTask) => task.id.toString())
        }
        .width('100%')
        .alignItems(ItemAlign.Stretch)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  // ── 历史记录 ──────────────────────────────────────────

  @Builder
  historyContent() {
    if (this.historyRecords.length === 0) {
      Column({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(32)
          .fontColor([$r('app.color.icon_empty')])
        Text($r('app.string.history_empty'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.pagePadding() })
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        Column() {
          Row() {
            Row({ space: 6 }) {
              ScopeSelect({
                label: this.str($r('app.string.history_filter_type_a11y')),
                value: this.historyKindLabel(),
                options: this.historyKindOptions(),
                onSelect: (_value: string): void => {
                  this.historyKind = HistoryKind.CONVERT
                }
              })
              ScopeSelect({
                label: this.str($r('app.string.history_filter_a11y')),
                value: this.historyFilterLabel(),
                options: this.historyFilterOptions(),
                onSelect: (value: string): void => {
                  this.historyFilter = value === this.str($r('app.string.history_filter_all')) ? '' : value
                }
              })
            }
            Blank()
            Button({ type: ButtonType.Normal }) {
              Text($r('app.string.action_clear_all'))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.danger'))
            }
            .height(40)
            .constraintSize({ minWidth: 84 })
            .padding({ left: 16, right: 16 })
            .backgroundColor($r('app.color.surface'))
            .borderRadius(LayoutSpec.controlRadius())
            .hoverEffect(HoverEffect.Highlight)
            .stateStyles({
              pressed: { .backgroundColor($r('app.color.danger_bg')) }
            })
            .onClick(() => {
              this.confirmClearHistory()
            })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
          .padding({ top: 4, bottom: 8 })

          if (this.filteredHistory().length === 0) {
            Column({ space: 12 }) {
              SymbolGlyph($r('sys.symbol.clock'))
                .fontSize(32)
                .fontColor([$r('app.color.icon_empty')])
              Text(this.historyEmptyText())
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
            .padding({ bottom: this.pagePadding() })
          } else {
            Grid() {
              ForEach(this.filteredHistory(), (record: HistoryRecord) => {
                GridItem() {
                  this.historyItem(record, this.historyRecords.indexOf(record))
                }
              }, (record: HistoryRecord) => record.timestamp + '_' + record.titleId + '_' + record.title)
            }
            .columnsTemplate('1fr 1fr')
            .columnsGap(8)
            .rowsGap(8)
            .width('100%')
            .layoutWeight(1)
            .align(Alignment.Top)
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.Spring)
          }
        }
        .width('100%')
        .layoutWeight(1)
        .constraintSize({ maxWidth: this.contentMaxWidth() })
        .padding({
          left: this.pagePadding(),
          right: this.pagePadding(),
          top: 8,
          bottom: this.pagePadding()
        })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
    }
  }

  @Builder
  historyItem(record: HistoryRecord, index: number) {
    Row({ space: 10 }) {
      GameCover({
        uri: this.historyIconUri(record),
        coverSize: 40,
        title: this.recordTitle(record)
      })

      Column({ space: 2 }) {
        Text(this.recordTitle(record))
          .fontSize(14)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Row({ space: 8 }) {
          Text(record.titleId)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(record.sizeGb + ' GB')
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.text_secondary'))
            .flexShrink(0)
        }
        .width('100%')
        Text(this.formatDate(record.timestamp))
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .maxLines(1)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .padding({ left: 12, right: 12, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .borderRadius(15)
    .clip(true)
    .bindContextMenu(this.historyDeleteMenu(index), ResponseType.LongPress)
    .bindContextMenu(this.historyDeleteMenu(index), ResponseType.RightClick)
  }

  @Builder
  historyDeleteMenu(index: number) {
    Menu() {
      MenuItem({ content: $r('app.string.detail_delete_record') })
        .contentFontColor($r('app.color.danger'))
        .onClick((): void => {
          this.confirmRemoveHistory(index)
        })
    }
  }

  private recordTitle(record: HistoryRecord): string {
    return record.title.length > 0 ? record.title : this.str($r('app.string.title_unknown'))
  }

  private historyKindOptions(): string[] {
    return [this.str($r('app.string.history_type_convert'))]
  }

  private historyKindLabel(): string {
    return this.str($r('app.string.history_type_convert'))
  }

  private historyFilterOptions(): string[] {
    const result: string[] = [this.str($r('app.string.history_filter_all'))]
    for (const option of CONSOLE_OPTIONS) {
      result.push(option)
    }
    return result
  }

  private historyFilterLabel(): string {
    return this.historyFilter.length === 0
      ? this.str($r('app.string.history_filter_all'))
      : this.historyFilter
  }

  private historyEmptyText(): Resource {
    if (this.historyFilter.length > 0) {
      return $r('app.string.history_empty_filtered')
    }
    return $r('app.string.history_empty')
  }

  private filteredHistory(): HistoryRecord[] {
    const result: HistoryRecord[] = []
    for (const record of this.historyRecords) {
      if (record.kind !== this.historyKind) {
        continue
      }
      if (this.historyFilter.length > 0 && record.consoleModel !== this.historyFilter) {
        continue
      }
      result.push(record)
    }
    return result
  }

  private confirmRemoveHistory(index: number): void {
    if (index < 0 || index >= this.historyRecords.length) {
      return
    }
    const options: promptAction.ShowDialogOptions = {
      title: this.str($r('app.string.history_delete_title')),
      message: this.str($r('app.string.history_delete_message'))
        .replace('%s', this.recordTitle(this.historyRecords[index])),
      buttons: [
        { text: this.str($r('app.string.action_cancel')), color: $r('app.color.text_secondary') },
        { text: this.str($r('app.string.action_delete')), color: $r('app.color.danger') }
      ]
    }
    this.getUIContext().getPromptAction().showDialog(options).then(
      (result: promptAction.ShowDialogSuccessResponse): void => {
        if (result.index === 1) {
          this.removeHistoryAt(index)
        }
      }).catch((): void => {
    })
  }

  private confirmClearHistory(): void {
    const options: promptAction.ShowDialogOptions = {
      title: this.str($r('app.string.history_clear_title')),
      message: this.str($r('app.string.history_clear_message')),
      buttons: [
        { text: this.str($r('app.string.action_cancel')), color: $r('app.color.text_secondary') },
        { text: this.str($r('app.string.action_clear_all')), color: $r('app.color.danger') }
      ]
    }
    this.getUIContext().getPromptAction().showDialog(options).then(
      (result: promptAction.ShowDialogSuccessResponse): void => {
        if (result.index === 1) {
          this.clearHistory()
        }
      }).catch((): void => {
    })
  }

  private clearHistory(): void {
    this.historyStore.clear()
    this.historyRecords = this.historyStore.getAll()
  }

  private removeHistoryAt(index: number): void {
    if (index < 0 || index >= this.historyRecords.length) {
      return
    }
    this.historyStore.removeAt(index)
    this.historyRecords = this.historyStore.getAll()
  }

  // ── 设置 ──────────────────────────────────────────────

  private async copyText(text: string, copiedMessage: Resource): Promise<void> {
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)
      await pasteboard.getSystemPasteboard().setData(data)
      this.getUIContext().getPromptAction().showToast({
        message: copiedMessage,
        duration: 2000
      })
    } catch (_e) {
      // ignore
    }
  }

  private languageLabel(): string {
    if (this.language === LANG_ZH) {
      return this.str($r('app.string.settings_language_zh'))
    }
    if (this.language === LANG_ZH_HANT) {
      return this.str($r('app.string.settings_language_zh_hant'))
    }
    if (this.language === LANG_EN) {
      return this.str($r('app.string.settings_language_en'))
    }
    if (this.language === LANG_JA) {
      return this.str($r('app.string.settings_language_ja'))
    }
    return this.str($r('app.string.settings_language_system'))
  }

  private setLanguage(mode: number): void {
    if (this.language === mode) {
      return
    }
    this.language = mode
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    LanguageStore.save(context, mode)
    LanguageStore.applyNow(context, mode)
    this.refreshLocalizedRuntimeText()
  }

  private colorModeLabel(): string {
    if (this.colorMode === MODE_DARK) {
      return this.str($r('app.string.settings_dark_mode_on'))
    }
    if (this.colorMode === MODE_LIGHT) {
      return this.str($r('app.string.settings_dark_mode_off'))
    }
    return this.str($r('app.string.settings_dark_mode_system'))
  }

  private setColorMode(mode: number): void {
    if (this.colorMode === mode) {
      return
    }
    this.colorMode = mode
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    ThemeStore.save(context, mode)
    ThemeStore.apply(context, mode)
  }

  private glowLabel(): string {
    if (this.glowLevel === GLOW_SOFT) {
      return this.str($r('app.string.settings_glow_soft'))
    }
    if (this.glowLevel === GLOW_CLEAR) {
      return this.str($r('app.string.settings_glow_clear'))
    }
    return this.str($r('app.string.settings_glow_standard'))
  }

  private setGlowLevel(level: number): void {
    if (this.glowLevel === level) {
      return
    }
    this.glowLevel = level
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    GlowStore.save(context, level)
  }

  // ── 系统底部 Tab 栏（手机 / 平板 / 窄窗口 PC） ─────────

  @Builder
  compactTabs() {
    Tabs({ barPosition: BarPosition.End, index: this.currentTab }) {
      TabContent() {
        this.homeContent()
      }
      .tabBar(this.tabBarStyle($r('app.string.tab_home'), $r('sys.symbol.house')))

      TabContent() {
        this.converterContent()
      }
      .tabBar(this.tabBarStyle($r('app.string.tab_convert'), $r('sys.symbol.arrow_down_square')))
    }
    .width('100%')
    .height('100%')
    .barMode(BarMode.Fixed)
    .barOverlap(true)
    .barFloatingStyle({
      // 手机不设宽度，由系统按屏宽自适应；平板以上收窄为居中悬浮条
      barWidth: {
        mediumBarWidth: LayoutSpec.TAB_BAR_WIDTH_MEDIUM,
        largeBarWidth: LayoutSpec.TAB_BAR_WIDTH_LARGE
      },
      barSideMargin: LayoutSpec.TAB_BAR_SIDE_MARGIN,
      barBottomMargin: LayoutSpec.TAB_BAR_BOTTOM_GAP,
      systemMaterial: this.tabBarMaterial()
    })
    .animationDuration(this.transitionDurationMs())
    .onChange((index: number) => {
      this.selectTab(index)
    })
  }

  private tabBarStyle(label: Resource, icon: Resource): BottomTabBarStyle {
    const normal = new SymbolGlyphModifier(icon)
    normal.fontColor([$r('app.color.text_secondary')])
    const selected = new SymbolGlyphModifier(icon)
    selected.fontColor([$r('app.color.accent')])
    const symbol: TabBarSymbol = {
      normal: normal,
      selected: selected
    }
    return BottomTabBarStyle.of(symbol, this.str(label))
      .labelStyle({
        selectedColor: $r('app.color.accent'),
        unselectedColor: $r('app.color.text_secondary'),
        maxLines: 1
      })
  }

  private tabBarMaterial(): uiMaterial.ImmersiveMaterial {
    return new uiMaterial.ImmersiveMaterial({
      style: GlowStore.barStyle(this.glowLevel),
      interactive: true,
      lightEffect: { color: $r('app.color.xbox_green') }
    })
  }

  // ── 文件选择与转换队列 ────────────────────────────────

  private async addIsoFiles(): Promise<void> {
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const options = new picker.DocumentSelectOptions()
      options.maxSelectNumber = 100
      options.fileSuffixFilters = ['.iso']

      const docPicker = new picker.DocumentViewPicker(context)
      const result = await docPicker.select(options)

      if (result.length === 0) {
        return
      }

      let added = 0
      for (const uri of result) {
        if (this.isDuplicateUri(uri)) {
          continue
        }

        const task = new ConversionTask()
        task.id = this.nextTaskId++
        task.isoUri = uri
        task.consoleModel = this.selectedDevice
        task.status = TaskStatus.ANALYZING
        this.setTaskProgress(task, $r('app.string.status_analyzing'))

        this.tasks = [...this.tasks, task]
        added++

        try {
          task.isoFile = fileIo.openSync(uri, fileIo.OpenMode.READ_ONLY)
          task.isoFd = task.isoFile.fd

          const raw: IsoInfoResult = xbigod.getIsoInfo(task.isoFd)

          if (raw.ok) {
            task.title = raw.title || ''
            task.titleId = raw.title_id || ''
            task.mediaId = raw.media_id || ''
            task.dataParts = raw.data_parts || 0
            task.dataSize = raw.data_size || 0
            task.isValid = true
            task.status = TaskStatus.READY
            this.clearTaskProgress(task)
          } else {
            task.status = TaskStatus.ERROR
            task.errorCode = raw.code ?? 'UNKNOWN'
            task.errorDetail = raw.detail ?? ''
          }
        } catch (err) {
          task.status = TaskStatus.ERROR
          task.errorCode = 'ISO_READ'
          task.errorDetail = (err as Error).message || ''
        }
        task.closeFile()
        if (task.isValid) {
          this.loadTaskIcon(task)
        }
      }

      if (added === 0) {
        return
      }
      this.setStatusForQueue()
    } catch (err) {
      this.statusText = this.str($r('app.string.status_read_error'))
        .replace('%s', (err as Error).message || '')
    }
  }

  private isDuplicateUri(uri: string): boolean {
    for (const task of this.tasks) {
      if (task.isoUri === uri) {
        return true
      }
    }
    return false
  }

  // ── GOD → ISO：选择文件夹添加 GOD 游戏包 ────────────────

  private isGodMode(): boolean {
    return this.selectedFormat === FORMAT_GOD_TO_ISO
  }

  private handleAddClick(): void {
    if (this.isGodMode()) {
      this.addGodFolders()
    } else {
      this.addIsoFiles()
    }
  }

  private async addGodFolders(): Promise<void> {
    if (this.godPicking) {
      return
    }
    this.godPicking = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const downloadDir = await this.acquireDownloadDir(context)
      if (downloadDir.length === 0) {
        this.statusText = this.str($r('app.string.status_permission_denied'))
        return
      }

      const options = new picker.DocumentSelectOptions()
      options.selectMode = picker.DocumentSelectMode.FOLDER
      options.maxSelectNumber = 1
      const docPicker = new picker.DocumentViewPicker(context)
      let result: string[] = []
      try {
        result = await docPicker.select(options)
      } catch (_e) {
        return
      }
      if (result.length === 0) {
        return
      }

      const folderPath = this.folderPathFromUri(result[0])
      if (folderPath.length === 0 || !this.isDirectoryPath(folderPath)) {
        this.statusText = this.str($r('app.string.god_folder_error'))
        return
      }

      const found = await this.discoverGodTasks(folderPath)
      if (found.length === 0) {
        this.statusText = this.str($r('app.string.god_folder_empty'))
        return
      }

      const next: ConversionTask[] = [...this.tasks]
      for (const task of found) {
        next.push(task)
      }
      this.tasks = next
      this.setStatusForQueue()
      for (const task of found) {
        this.loadTaskIcon(task)
      }
    } catch (_e) {
      this.statusText = this.str($r('app.string.god_folder_error'))
    } finally {
      this.godPicking = false
    }
  }

  private folderPathFromUri(uri: string): string {
    let path = ''
    try {
      path = new fileUri.FileUri(uri).path
    } catch (_e) {
      return ''
    }
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1)
    }
    return path
  }

  /** 只在用户选中的文件夹内查找 GOD 包：无扩展名的头文件 + 同名 .data 目录 */
  private async discoverGodTasks(folderPath: string): Promise<ConversionTask[]> {
    const found: ConversionTask[] = []
    const slash = folderPath.lastIndexOf('/')
    const baseName = slash >= 0 ? folderPath.substring(slash + 1) : folderPath
    if (baseName.endsWith('.data')) {
      // 用户直接选中了 xxx.data 目录，头文件在它旁边
      const headerPath = folderPath.substring(0, folderPath.length - 5)
      if (!this.isDuplicateGodPath(headerPath)) {
        const task = this.createGodTask(headerPath, folderPath)
        if (task !== null) {
          found.push(task)
        }
      }
      return found
    }

    const dirs: string[] = [folderPath]
    const depths: number[] = [0]
    let head = 0
    while (head < dirs.length && found.length < GOD_FOLDER_MAX_RESULTS &&
      head < GOD_FOLDER_MAX_DIRS) {
      const dir = dirs[head]
      const depth = depths[head]
      head++
      let names: string[] = []
      try {
        names = fileIo.listFileSync(dir)
      } catch (_e) {
        names = []
      }
      for (const name of names) {
        if (found.length >= GOD_FOLDER_MAX_RESULTS) {
          break
        }
        if (name.length === 0 || name.startsWith('.')) {
          continue
        }
        const path = dir + '/' + name
        let isDir = false
        try {
          isDir = fileIo.statSync(path).isDirectory()
        } catch (_e) {
          continue
        }
        if (isDir) {
          if (depth + 1 <= GOD_FOLDER_MAX_DEPTH && !name.endsWith('.data') &&
            dirs.length < GOD_FOLDER_MAX_DIRS) {
            dirs.push(path)
            depths.push(depth + 1)
          }
          continue
        }
        if (name.indexOf('.') >= 0) {
          continue
        }
        if (this.isDuplicateGodPath(path)) {
          continue
        }
        const dataDirPath = path + '.data'
        if (!this.isDirectoryPath(dataDirPath) || !this.pathExists(dataDirPath + '/Data0000')) {
          continue
        }
        const task = this.createGodTask(path, dataDirPath)
        if (task !== null) {
          found.push(task)
        }
      }
      if (head % GOD_FOLDER_SCAN_BATCH === 0) {
        await this.yieldToUi()
      }
    }
    return found
  }

  private createGodTask(headerPath: string, dataDirPath: string): ConversionTask | null {
    let headerFile: fileIo.File | null = null
    try {
      headerFile = fileIo.openSync(headerPath, fileIo.OpenMode.READ_ONLY)
      const raw: GodInfoResult = xbigod.getGodInfo(headerFile.fd)
      if (!raw.ok) {
        return null
      }
      const task = new ConversionTask()
      task.id = this.nextTaskId++
      task.direction = TaskDirection.GOD_TO_ISO
      task.isoUri = headerPath
      task.godHeaderPath = headerPath
      task.godDataDirPath = dataDirPath
      task.title = raw.title || ''
      task.titleId = raw.title_id || ''
      task.mediaId = raw.media_id || ''
      task.dataParts = raw.data_parts || 0
      task.dataSize = raw.data_size || 0
      task.consoleModel = this.selectedDevice
      task.isValid = true
      task.status = TaskStatus.READY
      return task
    } catch (_e) {
      return null
    } finally {
      if (headerFile !== null) {
        try { fileIo.closeSync(headerFile) } catch (_e) { /* ignore */ }
      }
    }
  }

  private yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout((): void => {
        resolve()
      }, 0)
    })
  }

  private isDuplicateGodPath(headerPath: string): boolean {
    for (const task of this.tasks) {
      if (task.direction === TaskDirection.GOD_TO_ISO && task.godHeaderPath === headerPath) {
        return true
      }
    }
    return false
  }

  private loadTaskIcon(task: ConversionTask): Promise<void> {
    if (!task.isValid) {
      return Promise.resolve()
    }
    const running = this.iconJobs.get(task.id)
    if (running !== undefined) {
      return running
    }
    if (task.iconChecked) {
      return Promise.resolve()
    }
    const job: Promise<void> = this.extractTaskIcon(task)
    this.iconJobs.set(task.id, job)
    job.then(() => {
      this.iconJobs.delete(task.id)
    }, () => {
      this.iconJobs.delete(task.id)
    })
    return job
  }

  private async extractTaskIcon(task: ConversionTask): Promise<void> {
    task.iconLoading = true
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const iconKey = this.iconKey(task.titleId)
      if (iconKey.length === 0) {
        return
      }

      const iconDir = context.filesDir + '/game_icons'
      if (!fileIo.accessSync(iconDir)) {
        try {
          fileIo.mkdirSync(iconDir, true)
        } catch (_e) {
          // 并发创建时目录可能已存在
        }
      }

      const iconPath = iconDir + '/' + iconKey + '.png'
      if (fileIo.accessSync(iconPath)) {
        this.applyTaskIcon(task, iconPath)
        return
      }

      const legacyPath = this.findLegacyIconPath(context.cacheDir + '/game_icons', iconKey)
      if (legacyPath.length > 0) {
        this.applyTaskIcon(task, legacyPath)
        return
      }

      if (task.direction === TaskDirection.GOD_TO_ISO) {
        const headerFile = fileIo.openSync(task.godHeaderPath, fileIo.OpenMode.READ_ONLY)
        try {
          const result: IconResult = await xbigod.extractGodIcon(headerFile.fd, iconPath)
          if (result.ok && fileIo.accessSync(iconPath)) {
            this.applyTaskIcon(task, iconPath)
          }
        } finally {
          fileIo.closeSync(headerFile)
        }
      } else {
        const isoFile = fileIo.openSync(task.isoUri, fileIo.OpenMode.READ_ONLY)
        try {
          const result: IconResult = await xbigod.extractGameIcon(isoFile.fd, iconPath)
          if (result.ok && fileIo.accessSync(iconPath)) {
            this.applyTaskIcon(task, iconPath)
          }
        } finally {
          fileIo.closeSync(isoFile)
        }
      }
    } catch (_err) {
      // 无内嵌图标或读取失败时保留占位封面，不影响转换流程
    } finally {
      task.iconLoading = false
      task.iconChecked = true
    }
  }

  private iconKey(titleId: string): string {
    return titleId.replace(/[^0-9A-Za-z_-]/g, '')
  }

  private findLegacyIconPath(dir: string, iconKey: string): string {
    try {
      if (!fileIo.accessSync(dir)) {
        return ''
      }
      const prefix = iconKey + '_'
      const names: string[] = fileIo.listFileSync(dir)
      for (let i = 0; i < names.length; i++) {
        if (names[i].startsWith(prefix)) {
          return dir + '/' + names[i]
        }
      }
    } catch (_e) {
      // ignore
    }
    return ''
  }

  private historyIconUri(record: HistoryRecord): string {
    const iconKey = this.iconKey(record.titleId)
    if (iconKey.length === 0) {
      return ''
    }
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext
      const iconPath = context.filesDir + '/game_icons/' + iconKey + '.png'
      if (fileIo.accessSync(iconPath)) {
        return fileUri.getUriFromPath(iconPath)
      }
      const legacyPath = this.findLegacyIconPath(context.cacheDir + '/game_icons', iconKey)
      if (legacyPath.length > 0) {
        return fileUri.getUriFromPath(legacyPath)
      }
    } catch (_e) {
      // ignore
    }
    return ''
  }

  private applyTaskIcon(task: ConversionTask, path: string): void {
    task.iconUri = fileUri.getUriFromPath(path)
  }

  private startableTaskCount(): number {
    let count = 0
    for (const task of this.tasks) {
      if (task.isValid &&
        (task.status === TaskStatus.READY ||
          task.status === TaskStatus.ERROR ||
          task.status === TaskStatus.CANCELLED)) {
        count++
      }
    }
    return count
  }

  private taskDisplayTitle(task: ConversionTask): string {
    return task.displayTitle.length > 0
      ? task.displayTitle
      : this.str($r('app.string.task_unknown_title'))
  }

  private confirmStartQueue(): void {
    if (this.queueRunning) {
      return
    }
    const count = this.startableTaskCount()
    if (count === 0) {
      return
    }
    const options: promptAction.ShowDialogOptions = {
      title: this.str($r('app.string.confirm_start_all_title')),
      message: this.str($r('app.string.confirm_start_all_message')).replace('%d', count.toString()),
      buttons: [
        { text: this.str($r('app.string.action_cancel')), color: $r('app.color.text_secondary') },
        { text: this.str($r('app.string.action_start_all')), color: $r('app.color.accent') }
      ]
    }
    this.getUIContext().getPromptAction().showDialog(options).then(
      (result: promptAction.ShowDialogSuccessResponse): void => {
        if (result.index === 1) {
          this.startQueue()
        }
      }).catch((): void => {
    })
  }

  private confirmStartTask(task: ConversionTask): void {
    if (this.queueRunning || !task.isValid) {
      return
    }
    const options: promptAction.ShowDialogOptions = {
      title: this.str($r('app.string.confirm_start_task_title')),
      message: this.str($r('app.string.confirm_start_task_message'))
        .replace('%s', this.taskDisplayTitle(task)),
      buttons: [
        { text: this.str($r('app.string.action_cancel')), color: $r('app.color.text_secondary') },
        { text: this.str($r('app.string.action_start_conversion')), color: $r('app.color.accent') }
      ]
    }
    this.getUIContext().getPromptAction().showDialog(options).then(
      (result: promptAction.ShowDialogSuccessResponse): void => {
        if (result.index === 1) {
          this.startTask(task)
        }
      }).catch((): void => {
    })
  }

  private confirmRemoveTask(task: ConversionTask): void {
    if (task.status === TaskStatus.CONVERTING) {
      return
    }
    const options: promptAction.ShowDialogOptions = {
      title: this.str($r('app.string.confirm_remove_task_title')),
      message: this.str($r('app.string.confirm_remove_task_message'))
        .replace('%s', this.taskDisplayTitle(task)),
      buttons: [
        { text: this.str($r('app.string.action_cancel')), color: $r('app.color.text_secondary') },
        { text: this.str($r('app.string.action_remove_task')), color: $r('app.color.danger') }
      ]
    }
    this.getUIContext().getPromptAction().showDialog(options).then(
      (result: promptAction.ShowDialogSuccessResponse): void => {
        if (result.index === 1) {
          this.removeTask(task)
        }
      }).catch((): void => {
    })
  }

  private startQueue(): void {
    if (this.queueRunning) {
      return
    }

    let pending = 0
    for (const task of this.tasks) {
      if (task.isValid &&
        (task.status === TaskStatus.ERROR || task.status === TaskStatus.CANCELLED)) {
        task.status = TaskStatus.READY
        task.errorCode = ''
        task.errorDetail = ''
        task.progress = 0
        this.clearTaskProgress(task)
      }
      if (task.status === TaskStatus.READY) {
        pending++
      }
    }
    if (pending === 0) {
      return
    }

    this.autoContinue = true
    this.queueCancelled = false
    this.cancelling = false
    this.queueRunning = true
    this.setStatusForQueue()
    this.processNext()
  }

  private startTask(task: ConversionTask): void {
    if (this.queueRunning || !task.isValid) {
      return
    }
    if (task.status === TaskStatus.ERROR || task.status === TaskStatus.CANCELLED) {
      task.status = TaskStatus.READY
      task.errorCode = ''
      task.errorDetail = ''
      task.progress = 0
      this.clearTaskProgress(task)
    }
    if (task.status !== TaskStatus.READY) {
      return
    }

    this.autoContinue = false
    this.queueCancelled = false
    this.cancelling = false
    this.queueRunning = true
    this.setStatusForQueue()
    this.runTask(task)
  }

  private processNext(): void {
    if (this.queueCancelled) {
      this.stopQueue()
      return
    }
    if (!this.autoContinue) {
      this.stopQueue()
      return
    }
    const next = this.findNextReadyTask()
    if (next === null) {
      this.stopQueue()
      return
    }
    this.runTask(next)
  }

  private stopQueue(): void {
    this.queueCancelled = false
    this.cancelling = false
    this.queueRunning = false
    this.currentTaskId = -1
    this.setStatusForQueue()
  }

  private findNextReadyTask(): ConversionTask | null {
    for (const task of this.tasks) {
      if (task.status === TaskStatus.READY) {
        return task
      }
    }
    return null
  }

  private findTask(id: number): ConversionTask | null {
    for (const task of this.tasks) {
      if (task.id === id) {
        return task
      }
    }
    return null
  }

  private removeTask(task: ConversionTask): void {
    if (task.status === TaskStatus.CONVERTING) {
      return
    }
    task.closeFile()
    const remaining: ConversionTask[] = []
    for (const t of this.tasks) {
      if (t.id !== task.id) {
        remaining.push(t)
      }
    }
    this.tasks = remaining
    this.setStatusForQueue()
  }

  private cancelCurrentTask(): void {
    if (!this.queueRunning || this.currentTaskId < 0 || this.cancelling) {
      return
    }
    this.queueCancelled = true
    this.cancelling = true
    this.setStatusForQueue()
    xbigod.cancelConversion()
  }

  private ensureTaskFile(task: ConversionTask): boolean {
    if (task.isoFd >= 0 && task.isoFile !== null) {
      return true
    }
    try {
      task.isoFile = fileIo.openSync(task.isoUri, fileIo.OpenMode.READ_ONLY)
      task.isoFd = task.isoFile.fd
      return true
    } catch (err) {
      task.errorCode = 'ISO_READ'
      task.errorDetail = (err as Error).message || ''
      return false
    }
  }

  private async runTask(task: ConversionTask): Promise<void> {
    if (task.direction === TaskDirection.GOD_TO_ISO) {
      await this.runGodToIsoTask(task)
    } else {
      await this.runIsoToGodTask(task)
    }
  }

  private async runIsoToGodTask(task: ConversionTask): Promise<void> {
    task.status = TaskStatus.CONVERTING
    task.progress = 0
    this.currentTaskId = task.id
    this.setTaskProgress(task, $r('app.string.progress_init'))
    task.errorCode = ''
    task.errorDetail = ''
    this.setStatusForQueue()

    if (!this.ensureTaskFile(task)) {
      task.status = TaskStatus.ERROR
      this.processNext()
      return
    }

    await this.loadTaskIcon(task)

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const downloadDir = await this.acquireDownloadDir(context)

    if (this.queueCancelled) {
      task.status = TaskStatus.CANCELLED
      task.progress = 0
      this.clearTaskProgress(task)
      task.closeFile()
      this.stopQueue()
      return
    }

    if (downloadDir.length === 0) {
      task.status = TaskStatus.ERROR
      task.errorCode = 'PERMISSION'
      task.errorDetail = ''
      task.closeFile()
      this.stopQueue()
      return
    }

    // 输出根：下载/<应用名>/Xbox360/GOD/<游戏名>/<TitleID>/00007000
    const rootDir = downloadDir + '/' + context.applicationInfo.name + '/' +
      this.deviceFolderName(task) + '/GOD'
    const gameDirPath = this.resolveGameDirPath(rootDir, task)
    const titleDirPath = gameDirPath + '/' + (task.titleId.length > 0 ? task.titleId : 'UNKNOWN')
    const contentDirPath = titleDirPath + '/00007000'
    const dataDirPath = contentDirPath + '/' + task.mediaId + '.data'
    const headerPath = contentDirPath + '/' + task.mediaId

    this.deleteRecursively(titleDirPath)

    if (!this.ensureDir(titleDirPath) || !this.ensureDir(contentDirPath) ||
      !this.ensureDir(dataDirPath)) {
      this.deleteRecursively(titleDirPath)
      task.status = TaskStatus.ERROR
      task.errorCode = 'WRITE_DIR'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    let headerFile: fileIo.File | null = null
    try {
      headerFile = fileIo.openSync(headerPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    } catch (_e) {
      this.deleteRecursively(titleDirPath)
      task.status = TaskStatus.ERROR
      task.errorCode = 'HEADER'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    const partFiles: fileIo.File[] = []
    const partFds: number[] = []
    this.setTaskProgress(task, $r('app.string.progress_creating_parts'), [task.dataParts])

    try {
      for (let i = 0; i < task.dataParts; i++) {
        const partName = 'Data' + i.toString().padStart(4, '0')
        const partPath = dataDirPath + '/' + partName
        const pf = fileIo.openSync(partPath,
          fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
        partFiles.push(pf)
        partFds.push(pf.fd)
      }
    } catch (_e) {
      this.cleanupFiles(headerFile, partFiles)
      this.deleteRecursively(titleDirPath)
      task.status = TaskStatus.ERROR
      task.errorCode = 'WRITE_PART'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    let converted = false
    try {
      await xbigod.convertIso(
        task.isoFd,
        headerFile.fd,
        partFds,
        (current: number, total: number, progressStage: number) => {
          this.updateTaskProgress(task, current, total, progressStage)
        }
      )
      converted = true
    } catch (err) {
      if (this.queueCancelled) {
        task.status = TaskStatus.CANCELLED
        task.progress = 0
        this.clearTaskProgress(task)
        task.closeFile()
        this.deleteRecursively(titleDirPath)
        this.stopQueue()
        return
      }
      const failure = err as NativeFailure
      this.setTaskProgress(task, $r('app.string.progress_aborted'))
      task.errorCode = failure.code ?? 'UNKNOWN'
      task.errorDetail = failure.detail ?? ''
      task.status = TaskStatus.ERROR
    } finally {
      this.cleanupFiles(headerFile, partFiles)
    }

    task.closeFile()

    if (!converted) {
      this.deleteRecursively(titleDirPath)
      this.processNext()
      return
    }

    task.progress = 100
    this.setTaskProgress(task, $r('app.string.progress_done'))
    task.status = TaskStatus.COMPLETED
    this.currentTaskId = -1

    const record = new HistoryRecord(
      task.displayTitle,
      task.titleId,
      task.sizeGb,
      Date.now(),
      task.consoleModel
    )
    this.historyStore.add(record)
    this.historyRecords = this.historyStore.getAll()

    this.processNext()
  }

  private async runGodToIsoTask(task: ConversionTask): Promise<void> {
    task.status = TaskStatus.CONVERTING
    task.progress = 0
    this.currentTaskId = task.id
    this.setTaskProgress(task, $r('app.string.progress_init'))
    task.errorCode = ''
    task.errorDetail = ''
    this.setStatusForQueue()

    await this.loadTaskIcon(task)

    let headerFile: fileIo.File | null = null
    try {
      headerFile = fileIo.openSync(task.godHeaderPath, fileIo.OpenMode.READ_ONLY)
    } catch (err) {
      task.status = TaskStatus.ERROR
      task.errorCode = 'GOD_HEADER'
      task.errorDetail = (err as Error).message || ''
      this.processNext()
      return
    }

    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    const downloadDir = await this.acquireDownloadDir(context)

    if (this.queueCancelled) {
      this.cleanupFiles(headerFile, [])
      task.status = TaskStatus.CANCELLED
      task.progress = 0
      this.clearTaskProgress(task)
      task.closeFile()
      this.stopQueue()
      return
    }

    if (downloadDir.length === 0) {
      this.cleanupFiles(headerFile, [])
      task.status = TaskStatus.ERROR
      task.errorCode = 'PERMISSION'
      task.errorDetail = ''
      task.closeFile()
      this.stopQueue()
      return
    }

    // 输出根：下载/<应用名>/Xbox360/ISO/<游戏名>.iso
    const rootDir = downloadDir + '/' + context.applicationInfo.name + '/' +
      this.deviceFolderName(task) + '/ISO'
    const isoPath = this.resolveIsoPath(rootDir, task)

    if (!this.ensureDir(rootDir)) {
      this.cleanupFiles(headerFile, [])
      task.status = TaskStatus.ERROR
      task.errorCode = 'WRITE_DIR'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    let isoFile: fileIo.File | null = null
    try {
      isoFile = fileIo.openSync(isoPath,
        fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC)
    } catch (_e) {
      this.cleanupFiles(headerFile, [])
      task.status = TaskStatus.ERROR
      task.errorCode = 'WRITE_ISO'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    const partFiles: fileIo.File[] = []
    const partFds: number[] = []
    try {
      for (let i = 0; i < task.dataParts; i++) {
        const partName = 'Data' + i.toString().padStart(4, '0')
        const partPath = task.godDataDirPath + '/' + partName
        const pf = fileIo.openSync(partPath, fileIo.OpenMode.READ_ONLY)
        partFiles.push(pf)
        partFds.push(pf.fd)
      }
    } catch (_e) {
      this.cleanupFiles(headerFile, partFiles)
      if (isoFile !== null) {
        try { fileIo.closeSync(isoFile) } catch (_e2) { /* ignore */ }
      }
      this.deleteRecursively(isoPath)
      task.status = TaskStatus.ERROR
      task.errorCode = 'GOD_PART'
      task.errorDetail = ''
      task.closeFile()
      this.processNext()
      return
    }

    let converted = false
    let cancelled = false
    try {
      await xbigod.convertGod(
        headerFile.fd,
        partFds,
        isoFile.fd,
        (current: number, total: number, progressStage: number) => {
          this.updateTaskProgress(task, current, total, progressStage)
        }
      )
      converted = true
    } catch (err) {
      if (this.queueCancelled) {
        cancelled = true
        task.status = TaskStatus.CANCELLED
        task.progress = 0
        this.clearTaskProgress(task)
      } else {
        const failure = err as NativeFailure
        this.setTaskProgress(task, $r('app.string.progress_aborted'))
        task.errorCode = failure.code ?? 'UNKNOWN'
        task.errorDetail = failure.detail ?? ''
        task.status = TaskStatus.ERROR
      }
    } finally {
      this.cleanupFiles(headerFile, partFiles)
      if (isoFile !== null) {
        try { fileIo.closeSync(isoFile) } catch (_e) { /* ignore */ }
      }
    }

    task.closeFile()

    if (cancelled) {
      this.deleteRecursively(isoPath)
      this.stopQueue()
      return
    }

    if (!converted) {
      this.deleteRecursively(isoPath)
      this.processNext()
      return
    }

    task.progress = 100
    this.setTaskProgress(task, $r('app.string.progress_done'))
    task.status = TaskStatus.COMPLETED
    this.currentTaskId = -1

    const record = new HistoryRecord(
      task.displayTitle,
      task.titleId,
      task.sizeGb,
      Date.now(),
      task.consoleModel
    )
    this.historyStore.add(record)
    this.historyRecords = this.historyStore.getAll()

    this.processNext()
  }

  private updateTaskProgress(task: ConversionTask, current: number, total: number,
    progressStage: number): void {
    if (total > 0) {
      task.progress = Math.min((current / total) * 99, 99)
    }

    if (task.direction === TaskDirection.GOD_TO_ISO) {
      if (progressStage === GOD_STAGE_READING_PARTS) {
        this.setTaskProgress(task, $r('app.string.progress_reading_part'), [current + 1, total])
      } else if (progressStage === GOD_STAGE_WRITING_HEADER) {
        this.setTaskProgress(task, $r('app.string.progress_writing_iso_header'))
        task.progress = 99
      } else if (progressStage === GOD_STAGE_FIXING_OFFSETS) {
        this.setTaskProgress(task, $r('app.string.progress_fixing_offsets'))
        task.progress = 99.5
      }
      return
    }

    if (progressStage === ProgressStage.WRITING_PARTS) {
      this.setTaskProgress(task, $r('app.string.progress_writing_part'), [current + 1, total])
    } else if (progressStage === ProgressStage.WRITING_MHT) {
      this.setTaskProgress(task, $r('app.string.progress_writing_mht'))
      task.progress = 99
    } else if (progressStage === ProgressStage.WRITING_HEADER) {
      this.setTaskProgress(task, $r('app.string.progress_writing_header'))
      task.progress = 99.5
    }
  }

  private readyTaskCount(): number {
    let count = 0
    for (const task of this.tasks) {
      if (task.status === TaskStatus.READY) {
        count++
      }
    }
    return count
  }

  private errorTaskCount(): number {
    let count = 0
    for (const task of this.tasks) {
      if (task.status === TaskStatus.ERROR) {
        count++
      }
    }
    return count
  }

  private hasReadyTasks(): boolean {
    return this.readyTaskCount() > 0
  }

  private hasErrorTasks(): boolean {
    return this.errorTaskCount() > 0
  }

  private allTasksCompleted(): boolean {
    if (this.tasks.length === 0) {
      return false
    }
    for (const task of this.tasks) {
      if (task.status !== TaskStatus.COMPLETED) {
        return false
      }
    }
    return true
  }

  private taskPosition(id: number): number {
    for (let i = 0; i < this.tasks.length; i++) {
      if (this.tasks[i].id === id) {
        return i + 1
      }
    }
    return 1
  }

  private formatResource(resId: number, args: (string | number)[]): string {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext
    if (args.length === 0) {
      return context.resourceManager.getStringSync(resId)
    }
    return context.resourceManager.getStringSync(resId, ...args)
  }

  private setTaskProgress(task: ConversionTask, res: Resource, args: (string | number)[] = []): void {
    task.progressResId = res.id
    task.progressArgs = args
    task.progressMessage = this.formatResource(res.id, args)
  }

  private clearTaskProgress(task: ConversionTask): void {
    task.progressResId = 0
    task.progressArgs = []
    task.progressMessage = ''
  }

  /** 语言切换后 @State/@Observed 里缓存的文案不会随资源刷新，需要按当前语言重算 */
  private refreshLocalizedRuntimeText(): void {
    this.setStatusForQueue()
    for (const task of this.tasks) {
      if (task.progressResId !== 0) {
        task.progressMessage = this.formatResource(task.progressResId, task.progressArgs)
      }
    }
  }

  private setStatusForQueue(): void {
    if (this.queueRunning) {
      const current = this.findTask(this.currentTaskId)
      if (this.cancelling) {
        this.statusText = this.str($r('app.string.progress_cancelling'))
      } else if (current !== null) {
        this.statusText = this.str($r('app.string.status_converting_queue'))
          .replace('%s', current.displayTitle)
          .replace('%d', this.taskPosition(current.id).toString())
          .replace('%d', this.tasks.length.toString())
      } else {
        this.statusText = this.str($r('app.string.status_queue_ready'))
          .replace('%d', this.readyTaskCount().toString())
      }
      return
    }

    if (this.tasks.length === 0) {
      this.statusText = this.str(this.isGodMode()
        ? $r('app.string.status_select_god')
        : $r('app.string.status_select_iso'))
    } else if (this.hasErrorTasks()) {
      this.statusText = this.str($r('app.string.status_queue_failed'))
    } else if (this.hasReadyTasks()) {
      this.statusText = this.str($r('app.string.status_queue_ready'))
        .replace('%d', this.readyTaskCount().toString())
    } else if (this.allTasksCompleted()) {
      this.statusText = this.str($r('app.string.status_queue_complete'))
    } else {
      this.statusText = this.str($r('app.string.status_queue_stopped'))
    }
  }

  private queueSummaryText(): string {
    return this.str($r('app.string.queue_summary'))
      .replace('%d', this.tasks.length.toString())
      .replace('%d', this.readyTaskCount().toString())
  }

  private taskErrorText(task: ConversionTask): string {
    if (task.status !== TaskStatus.ERROR || task.errorCode.length === 0) {
      return ''
    }
    const reason = this.errorReason(task.errorCode)
    if (task.errorDetail.length > 0) {
      return reason + ' (' + task.errorDetail + ')'
    }
    return reason
  }

  private errorReason(code: string): string {
    if (code === 'ISO_READ') {
      return this.str($r('app.string.error_iso_read'))
    } else if (code === 'PART_COUNT_MISMATCH') {
      return this.str($r('app.string.error_part_count_mismatch'))
    } else if (code === 'WRITE_PART') {
      return this.str($r('app.string.error_write_part'))
    } else if (code === 'MHT') {
      return this.str($r('app.string.error_mht'))
    } else if (code === 'HEADER') {
      return this.str($r('app.string.error_header'))
    } else if (code === 'PERMISSION') {
      return this.str($r('app.string.status_permission_denied'))
    } else if (code === 'WRITE_DIR') {
      return this.str($r('app.string.status_create_output_dir_failed'))
    } else if (code === 'GOD_HEADER') {
      return this.str($r('app.string.error_god_header'))
    } else if (code === 'GOD_PART') {
      return this.str($r('app.string.error_god_part'))
    } else if (code === 'WRITE_ISO') {
      return this.str($r('app.string.error_write_iso'))
    }
    return this.str($r('app.string.error_unknown'))
  }

  private async acquireDownloadDir(context: common.UIAbilityContext): Promise<string> {
    let granted = false
    try {
      const atManager = abilityAccessCtrl.createAtManager()
      const result = await atManager.requestPermissionsFromUser(context,
        ['ohos.permission.READ_WRITE_DOWNLOAD_DIRECTORY'])
      granted = result.authResults.length > 0 && result.authResults[0] === 0
    } catch (err) {
      granted = false
    }

    if (!granted) {
      return ''
    }

    try {
      return Environment.getUserDownloadDir()
    } catch (err) {
      return ''
    }
  }

  private resolveGameDirPath(rootDir: string, task: ConversionTask): string {
    const baseName = this.outputFolderName(task)
    let candidate = rootDir + '/' + baseName
    for (let index = 2; index <= 99; index++) {
      if (!this.pathExists(candidate) || this.isDirectoryPath(candidate)) {
        return candidate
      }
      candidate = rootDir + '/' + baseName + ' (' + index.toString() + ')'
    }
    return rootDir + '/' + baseName + ' (' + task.titleId + ')'
  }

  private resolveIsoPath(rootDir: string, task: ConversionTask): string {
    const baseName = this.outputFolderName(task)
    let candidate = rootDir + '/' + baseName + '.iso'
    for (let index = 2; index <= 99; index++) {
      if (!this.pathExists(candidate)) {
        return candidate
      }
      candidate = rootDir + '/' + baseName + ' (' + index.toString() + ').iso'
    }
    return rootDir + '/' + baseName + ' (' + task.titleId + ').iso'
  }

  private ensureDir(path: string): boolean {
    if (this.isDirectoryPath(path)) {
      return true
    }
    try {
      fileIo.mkdirSync(path, true)
      return true
    } catch (_e) {
      return this.isDirectoryPath(path)
    }
  }

  private deviceFolderName(task: ConversionTask): string {
    const name = task.consoleModel.replace(/\s+/g, '')
    return name.length > 0 ? name : 'Xbox360'
  }

  private outputFolderName(task: ConversionTask): string {
    let name: string = task.displayTitle.trim()
    name = name.replace(/[\\/:*?"<>|]/g, '_')
    name = name.replace(/[. ]+$/, '')
    if (name.length === 0) {
      name = task.titleId.length > 0 ? task.titleId : 'Unknown'
    }
    if (name.length > 80) {
      name = name.substring(0, 80)
      name = name.replace(/[. ]+$/, '')
    }
    const upper = name.toUpperCase()
    if (upper === 'CON' || upper === 'PRN' || upper === 'AUX' || upper === 'NUL' ||
      /^COM[1-9]$/.test(upper) || /^LPT[1-9]$/.test(upper)) {
      name = name + '_'
    }
    return name
  }

  private isDirectoryPath(path: string): boolean {
    try {
      return fileIo.statSync(path).isDirectory()
    } catch (_e) {
      return false
    }
  }

  private pathExists(path: string): boolean {
    try {
      return fileIo.accessSync(path)
    } catch (_e) {
      return false
    }
  }

  private deleteRecursively(path: string): void {
    let exists = false
    try {
      exists = fileIo.accessSync(path)
    } catch (_e) {
      exists = false
    }
    if (!exists) {
      return
    }

    let isDir = false
    try {
      isDir = fileIo.statSync(path).isDirectory()
    } catch (_e) {
      return
    }

    if (!isDir) {
      try { fileIo.unlinkSync(path) } catch (_e) { /* ignore */ }
      return
    }

    let children: string[] = []
    try {
      children = fileIo.listFileSync(path)
    } catch (_e) {
      return
    }
    for (const name of children) {
      this.deleteRecursively(path + '/' + name)
    }
    try { fileIo.rmdirSync(path) } catch (_e) { /* ignore */ }
  }

  private cleanupFiles(headerFile: fileIo.File | null, partFiles: fileIo.File[]): void {
    if (headerFile !== null) {
      try { fileIo.closeSync(headerFile) } catch (_e) { /* ignore */ }
    }
    for (const pf of partFiles) {
      try { fileIo.closeSync(pf) } catch (_e) { /* ignore */ }
    }
  }

  private formatDate(timestamp: number): string {
    const d: Date = new Date(timestamp)
    const y: string = d.getFullYear().toString()
    const m: string = (d.getMonth() + 1).toString().padStart(2, '0')
    const day: string = d.getDate().toString().padStart(2, '0')
    const h: string = d.getHours().toString().padStart(2, '0')
    const min: string = d.getMinutes().toString().padStart(2, '0')
    return y + '-' + m + '-' + day + ' ' + h + ':' + min
  }
}
