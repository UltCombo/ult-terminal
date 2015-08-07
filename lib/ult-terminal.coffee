UltTerminalView = require './ult-terminal-view'

module.exports =
  cliStatusView: null

  activate: (state) ->
    createStatusEntry = =>
      @cliStatusView = new UltTerminalView(state.cliStatusViewState)
    atom.packages.onDidActivateInitialPackages => createStatusEntry()

  deactivate: ->
    @cliStatusView.destroy()

  config:
    paneWidth:
      type: 'integer'
      default: 520
    clearCommandInput:
      type: 'boolean'
      default: true
    logConsole:
      type: 'boolean'
      default: false
