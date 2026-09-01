import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "nugget210.oma-sleeper"

  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false
  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function togglePanel() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = Qt.binding(function() { return root.settings })
    target.anchorItem = button
    target.hostWidget = root
  }
  function siblingWidgets() {
    return root.bar && typeof root.bar.moduleWidgets === "function"
      ? root.bar.moduleWidgets(root.moduleName) : [root]
  }
  function publishSettings(entry) {
    var widgets = siblingWidgets()
    for (var i = 0; i < widgets.length; i++)
      if (widgets[i] && typeof widgets[i].receiveSettings === "function") widgets[i].receiveSettings(entry)
  }
  function receiveSettings(entry) { root.settings = entry }
  function publishData(value) {
    var widgets = siblingWidgets()
    for (var i = 0; i < widgets.length; i++)
      if (widgets[i] && typeof widgets[i].receiveData === "function") widgets[i].receiveData(value)
  }
  function receiveData(value) { if (panelLoader.item) panelLoader.item.data = value }
  function publishPreview(scenario) {
    var widgets = siblingWidgets()
    for (var i = 0; i < widgets.length; i++)
      if (widgets[i] && typeof widgets[i].receivePreview === "function") widgets[i].receivePreview(scenario)
  }
  function receivePreview(scenario) { if (panelLoader.item) panelLoader.item.previewScenario = scenario }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight
  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()

  Loader {
    id: panelLoader
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: { root.injectPanel(); Qt.callLater(root.injectPanel) }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: panelLoader.item ? panelLoader.item.barText : "NFL …"
    foreground: panelLoader.item ? panelLoader.item.barColor : (root.bar ? root.bar.foreground : Color.foreground)
    horizontalMargin: 8.75
    verticalPadding: 8.75
    onPressed: function(b) {
      if (b === Qt.MiddleButton && panelLoader.item) panelLoader.item.refresh()
      else root.togglePanel()
    }
  }
}
