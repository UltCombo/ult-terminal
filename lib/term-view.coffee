fs = require 'fs-plus'
{resolve} = require 'path'
{exec} = require 'child_process'
{View, TextEditorView} = require 'atom-space-pen-views'
SubAtom = require 'sub-atom'
ansihtml = require 'ansi-html-stream'
kill = require 'tree-kill'
require('fix-path')()

lastOpenedView = null

# Regular expression adapted from http://blog.mattheworiordan.com/post/13174566389/url-regular-expression-for-links-with-or-without
# Cleaned up invalid/unnecessary escapes, added negative lookahead to not match package@semver as an email address.
rUrl = /(?:(?:(?:[A-Za-z]{3,9}:(?:\/\/)?)(?:[-;:&=+$,.\w]+@(?!\d+\b))?[A-Za-z0-9.-]+|(www\.|[-;:&=+$,.\w]+@(?!\d+\b))[A-Za-z0-9.-]+)(?:(?:\/[+~%/.\w_-]*)?\??(?:[-+=&;%@.\w]*)#?(?:[.!/\\\w]*))?)/g

module.exports =
class TermView extends View
  @content: ->
    @div tabIndex: -1, class: 'panel panel-right ult-terminal', =>
      @div class: 'panel-heading', =>
        @div class: 'running-process-actions hide', outlet: 'runningProcessActions', =>
          @div class: 'btn-group pull-left', =>
            @button click: 'interrupt', class: 'btn', title: 'Send SIGINT to the running process (similar to pressing Ctrl+C in a regular terminal)', =>
              @span 'Interrupt'
            @button click: 'kill', class: 'btn', title: 'Send SIGKILL to the entire running process tree', =>
              @span 'Kill'
          @span ' running process', class: 'ult-terminal-heading-text pull-left'

        @div class: 'btn-group', =>
          @button click: 'clearOutput', class: 'btn', title: 'Clear the terminal output', =>
            @span 'Clear'
          @button click: 'close', class: 'btn', title: 'Hide the terminal (Shift+Enter)', =>
            @span 'Hide'
          @button click: 'quit', class: 'btn', title: 'Kill the running process (if any) and destroy the terminal session', =>
            @span 'Quit'
      @div class: 'cli-panel-body', =>
        @pre tabIndex: -1, class: 'terminal native-key-bindings', outlet: 'cliOutput',
          'Welcome to ult-terminal.\n'
        @subview 'cmdEditor', new TextEditorView(mini: true, placeholderText: 'input your command here')

  initialize: (statusIcon, statusView) ->
    @statusIcon = statusIcon
    @statusView = statusView
    @cwd = null
    @subs = new SubAtom

    @subs.add @statusIcon, 'click', =>
      @toggle()

    @subs.add atom.config.observe 'ult-terminal.paneWidth', (paneWidth) =>
      @css 'width', paneWidth

    @subs.add this, 'click', '[data-targettype]', ->
      atom.workspace.open @dataset.target if @dataset.targettype is 'file'

  readLine: ->
    return if this isnt lastOpenedView

    inputCmd = @cmdEditor.getModel().getText().trim()

    @appendOutput "$ #{inputCmd}\n"
    # support 'a b c' and "foo bar"
    args = inputCmd.match(/("[^"]*"|'[^']*'|[^\s'"]+)/g) ? []
    cmd = args.shift()
    if not cmd
      return
    if cmd == 'cd'
      return @cd args
    if cmd == 'ls' and !args.length
      return @ls()
    if cmd == 'clear'
      return @clear()
    if cmd == 'exit'
      return @destroy()
    @spawn inputCmd

  appendOutput: (output) ->
    doScroll = @isScrolledToBottom()
    @cliOutput.append output
    @scrollToBottom() if doScroll

  showCmd: ->
    doScroll = @isScrolledToBottom()
    @cmdEditor.show()
    @scrollToBottom() if doScroll
    if atom.config.get('ult-terminal.clearCommandInput')
      @cmdEditor.setText('')
    else
      @cmdEditor.getModel().selectAll()
    @cmdEditor.focus()

  scrollToBottom: ->
    @cliOutput[0].scrollTop = @cliOutput[0].scrollHeight

  isScrolledToBottom: ->
    el = @cliOutput[0]
    el.scrollTop + el.offsetHeight is el.scrollHeight

  flashStatusIconClass: (className, time = 100) ->
    @statusIcon.classList.add className
    clearTimeout @statusIconFlashTimeout if @statusIconFlashTimeout
    @statusIconFlashTimeout = setTimeout (=> @statusIcon.classList.remove className), time

  resetStatusIcon: ->
    clearTimeout @statusIconFlashTimeout if @statusIconFlashTimeout
    @statusIcon.classList.remove 'status-running', 'status-info', 'status-success', 'status-error'

  destroy: (doKill = true) ->
    _destroy = =>
      @close() if @hasParent()
      @statusIcon.parentNode.removeChild @statusIcon
      @statusView.removeTermView this
      @subs.dispose()
    if @program
      @program.once 'exit', _destroy
      @kill() if doKill
    else
      _destroy()

  quit: ->
    @destroy()

  kill: ->
    if @program
      kill @program.pid, 'SIGKILL', (err) ->
        console.log err if err and atom.config.get('ult-terminal.debug')

  interrupt: ->
    if @program
      # Send the interrupt signal to the root child process only, it should propagate from there.
      @program.kill 'SIGINT'

  open: ->
    @lastLocation = atom.workspace.getActivePane()

    @pane = atom.workspace.addRightPanel(item: this) unless @hasParent()

    if lastOpenedView and lastOpenedView != this
      lastOpenedView.close()
    lastOpenedView = this
    @scrollToBottom()
    @statusView.setActiveTermView this
    @cmdEditor.focus()

  close: ->
    @lastLocation.activate()
    @detach()
    @pane?.destroy()
    lastOpenedView = null

  toggle: ->
    if @hasParent()
      @close()
    else
      @open()

  cd: (args) ->
    dir = args[0] ? @getCwd()
    resolvedDir = resolve @getCwd(), fs.normalize dir
    fs.stat resolvedDir, (err, stat) =>
      if err
        if err.code == 'ENOENT'
          return @errorMessage "cd: #{dir}: No such file or directory"
        return @errorMessage err.message
      if not stat.isDirectory()
        return @errorMessage "cd: not a directory: #{dir}"
      @cwd = resolvedDir
      @message "cwd: #{@cwd}"

  ls: ->
    files = fs.readdirSync @getCwd()
    filesBlocks = []
    files.forEach (filename) =>
      try
        filesBlocks.push @_fileInfoHtml filename, @getCwd(), ['file-info']
      catch
        console.log "#{filename} couln't be read"
    filesBlocks = filesBlocks.sort (a, b)->
      aDir = a[1].isDirectory()
      bDir = b[1].isDirectory()
      if aDir and not bDir
        return -1
      if not aDir and bDir
        return 1
      a[2] > b[2] and 1 or -1
    filesBlocks = filesBlocks.map (b) ->
      b[0]
    @message filesBlocks.join('') + '<div class="clear"/>'

  clear: ->
    @clearOutput()
    @message ''
    @cmdEditor.setText ''

  # Used by the "Clear" button and the `clear` command
  clearOutput: ->
    @cliOutput.empty()

  _fileInfoHtml: (filename, parent, extraClasses = []) ->
    classes = ['icon'].concat extraClasses
    filepath = parent + '/' + filename
    stat = fs.lstatSync filepath
    if stat.isSymbolicLink()
      # classes.push 'icon-file-symlink-file'
      classes.push 'stat-link'
      stat = fs.statSync filepath
      targetType = 'null'
    if stat.isFile()
      if stat.mode & 73 #0111
        classes.push 'stat-program'
      # TODO check extension
      classes.push 'icon-file-text'
      targetType = 'file'
    if stat.isDirectory()
      classes.push 'icon-file-directory'
      targetType = 'directory'
    if stat.isCharacterDevice()
      classes.push 'stat-char-dev'
      targetType = 'device'
    if stat.isFIFO()
      classes.push 'stat-fifo'
      targetType = 'fifo'
    if stat.isSocket()
      classes.push 'stat-sock'
      targetType = 'sock'
    if filename[0] == '.'
      classes.push 'status-ignored'
    # if statusName = @getGitStatusName filepath
    #   classes.push statusName
    # other stat info
    ["<span class=\"#{classes.join ' '}\" data-targettype=\"#{targetType}\" data-target=\"#{filepath}\">#{filename}</span>", stat, filename]

  linkify: (str) ->
    escapedCwd = @getCwd().split(/[\\/]/g).map((segment) -> segment.replace /\W/g, '\\$&').join '[\\\\/]'
    rFilepath = new RegExp escapedCwd + '[\\\\/]([^\\n\\r\\t:#$%^&!:<>]+\\.?[^\\n\\r\\t:#$@%&*^!:.+,\\\\/"<>]*)', 'ig'
    str.replace rFilepath, (match, relativeFilepath) =>
      try
        @_fileInfoHtml(relativeFilepath, @getCwd())[0]
      catch err
        match
    .replace rUrl, (match, protocolLessBeginning) ->
      if protocolLessBeginning
        href = (if protocolLessBeginning is 'www.' then 'http://' else 'mailto:') + match
      else
        href = match
      "<a href='#{href}'>#{match}</a>"

  # getGitStatusName: (path, gitRoot, repo) ->
  #   status = (repo.getCachedPathStatus or repo.getPathStatus)(path)
  #   if status
  #     if repo.isStatusModified status
  #       return 'modified'
  #     if repo.isStatusNew status
  #       return 'added'
  #   if repo.isPathIgnore path
  #     return 'ignored'

  message: (message) ->
    @appendOutput @linkify(if message.endsWith('\n') then message else message + '\n') if message
    @showCmd()
    @statusIcon.classList.remove 'status-error'
    @statusIcon.classList.add 'status-success'

  errorMessage: (message) ->
    @appendOutput @linkify(if message.endsWith('\n') then message else message + '\n') if message
    @showCmd()
    @statusIcon.classList.remove 'status-success'
    @statusIcon.classList.add 'status-error'

  getCwd: ->
    return @cwd if @cwd?
    editorPath = atom.workspace.getActiveTextEditor()?.getPath()
    activeRootDir = null
    return @cwd = activeRootDir.path if editorPath and atom.project.rootDirectories.some (rootDir) ->
      if rootDir.contains(editorPath)
        activeRootDir = rootDir
        true
    @cwd = atom.project.rootDirectories[0]?.path ? fs.getHomeDirectory()

  spawn: (inputCmd) ->
    # @program = spawn cmd, args, stdio: 'pipe', env: process.env, cwd: @getCwd()
    @program = exec inputCmd, stdio: 'pipe', env: process.env, cwd: @getCwd()
    @resetStatusIcon()
    @statusIcon.classList.add 'status-running'
    @runningProcessActions.removeClass 'hide'
    @cmdEditor.hide()

    onExit = (statusIconClass) =>
      onExit = -> # noop
      @program = null
      @resetStatusIcon()
      @statusIcon.classList.add statusIconClass
      @runningProcessActions.addClass 'hide'
      @showCmd()

    htmlStream = ansihtml()
    htmlStream.on 'data', (data) =>
      return if not data
      @appendOutput @linkify data
    @program.stdout.pipe htmlStream
    @program.stderr.pipe htmlStream

    @program.on 'exit', (code) =>
      console.log 'exit', code if atom.config.get('ult-terminal.debug')
      onExit(if code == 0 then 'status-success' else 'status-error')
    @program.on 'error', (err) =>
      console.log 'error', err if atom.config.get('ult-terminal.debug')
      onExit 'status-error'
    @program.stdout.on 'data', =>
      @statusIcon.classList.remove 'status-error'
      @flashStatusIconClass 'status-info'
    @program.stderr.on 'data', =>
      console.log 'stderr' if atom.config.get('ult-terminal.debug')
      @statusIcon.classList.add 'status-error'
