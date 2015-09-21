StatusView = require './status-view'

module.exports =
  activate: ->
    @statusView = new StatusView
    cb = =>
      @statusView.createTermView()
      @statusView.attach()
    if atom.packages.isPackageActive 'status-bar'
      cb()
    else
      @statusView.subs.add atom.packages.onDidActivateInitialPackages cb

  deactivate: ->
    @statusView.destroy()
    @statusView = null

  config:
    paneWidth:
      title: 'Pane width (px)'
      type: 'integer'
      default: 520
    clearCommandInput:
      title: 'Clear command input after submitting command'
      type: 'boolean'
      default: true
    debug:
      title: 'Output debugging information to console'
      type: 'boolean'
      default: false
