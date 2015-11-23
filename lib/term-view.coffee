fs = require 'fs-plus'
{resolve, dirname} = require 'path'
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
      @div class: 'panel-heading', outlet: 'heading', =>
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
          @button click: 'destroy', class: 'btn', title: 'Kill the running process (if any) and destroy the terminal session', =>
            @span 'Quit'
      @pre tabIndex: -1, class: 'terminal native-key-bindings', outlet: 'cliOutput',
        'Welcome to ult-terminal.\n'
      @subview 'cmdEditor', new TextEditorView(mini: true, placeholderText: 'input your command here')

  initialize: (statusIcon, statusView, commandHistory) ->
    @statusIcon = statusIcon
    @statusView = statusView
    @commandHistory = commandHistory
    @commandHistoryIndex = null
    @commandHistorySearchBuffer = null
    @cwd = null
    @subs = new SubAtom

    @subs.add @statusIcon, 'click', =>
      @toggle()

    @subs.add atom.config.observe 'ult-terminal.paneWidth', (paneWidth) =>
      @css 'width', paneWidth

    @subs.add this, 'click', '[data-targettype]', ->
      atom.workspace.open @dataset.target if @dataset.targettype is 'file'

    @subs.add @cmdEditor, 'keydown', (event) =>
      return unless direction = { 38: -1, 40: 1 }[event.keyCode]
      event.preventDefault()
      event.stopPropagation()

      @commandHistorySearchBuffer = @cmdEditor.getModel().getText() if not @commandHistoryIndex?

      predicate = (idx) =>
        command = @commandHistory[idx]
        if command.startsWith @commandHistorySearchBuffer
          @cmdEditor.getModel().setText command
          @commandHistoryIndex = idx
          true

      if direction < 0
        (break if predicate idx) for idx in [(@commandHistoryIndex ? @commandHistory.length) - 1..0] by -1
        null # prevent syntax error
      else
        (break if found = predicate idx) for idx in [@commandHistoryIndex + 1...@commandHistory.length] by 1 if @commandHistoryIndex?
        if not found
          @cmdEditor.getModel().setText @commandHistorySearchBuffer
          @commandHistoryIndex = null

    for btn in @heading.find 'button[title]'
      @subs.add atom.tooltips.add btn, {}

  readLine: ->
    inputCmd = @cmdEditor.getModel().getText()

    @appendOutput "$ #{inputCmd}\n"
    # support 'a b c' and "foo bar"
    args = inputCmd.match(/("[^"]*"|'[^']*'|[^\s'"]+)/g) ? []
    cmd = args.shift()
    return @showCmd() if not cmd

    @addCommandHistoryEntry inputCmd

    if cmd == 'cd'
      return @cd args
    if cmd == 'pwd'
      return @pwd()
    if cmd == 'ls' and !args.length
      return @ls()
    if cmd in ['clear', 'cls']
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
    if atom.config.get 'ult-terminal.clearCommandInput'
      @cmdEditor.setText ''
    else
      @cmdEditor.getModel().selectAll()
    @cmdEditor.focus()
    @commandHistoryIndex = null

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

  destroy: ->
    _destroy = =>
      @close() if @hasParent()
      @statusIcon.parentNode.removeChild @statusIcon
      @statusView.removeTermView this
      @subs.dispose()
    if @program
      @program.once 'exit', _destroy
      @kill()
    else
      _destroy()

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

    lastOpenedView.close() if lastOpenedView and lastOpenedView != this
    lastOpenedView = this
    @scrollToBottom()
    @statusView.setActiveTermView this
    @cmdEditor.focus()
    @statusIcon.classList.add 'status-opened'

  close: ->
    @lastLocation.activate()
    @detach()
    @pane?.destroy()
    lastOpenedView = null
    @statusIcon.classList.remove 'status-opened'

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
          return @message "cd: #{dir}: No such file or directory", true
        return @message err.message, true
      if not stat.isDirectory()
        return @message "cd: not a directory: #{dir}", true
      @cwd = resolvedDir
      @message @getCwd()

  pwd: ->
    @message @getCwd()

  ls: ->
    files = fs.readdirSync @getCwd()
    filesBlocks = []
    files.forEach (filename) =>
      try
        filesBlocks.push @_fileInfoHtml filename, @getCwd(), ['file-info']
      catch
        console.log "#{filename} couln't be read"
    filesBlocks = filesBlocks.sort (a, b) ->
      aDir = a[1].isDirectory()
      bDir = b[1].isDirectory()
      if aDir and not bDir
        return -1
      if not aDir and bDir
        return 1
      if a[2] > b[2] then 1 else -1
    filesBlocks = filesBlocks.map (b) ->
      b[0]
    @message filesBlocks.join('') + '<div class="clear"></div>'

  clear: ->
    @clearOutput()
    @message ''

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

  message: (message, isError = false) ->
    @appendOutput @linkify(if message.endsWith('\n') then message else message + '\n') if message
    @showCmd()
    @resetStatusIcon()
    @statusIcon.classList.add(if isError then 'status-error' else 'status-success')

  getCwd: ->
    return @cwd if @cwd?
    validRootDirs = atom.project.rootDirectories.filter (rootDir) ->
      not rootDir.path.startsWith 'atom://'
    editorPath = atom.workspace.getActiveTextEditor()?.getPath()
    activeRootDir = null
    @cwd =
      if (editorPath and validRootDirs.some (rootDir) ->
        if rootDir.contains editorPath
          activeRootDir = rootDir
          true
      )
        activeRootDir.path
      else
        validRootDirs[0]?.path ? fs.getHomeDirectory()

    @cwd = dirname @cwd if try fs.statSync(@cwd).isDirectory() is false
    @cwd

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
      console.log 'exit', code if atom.config.get 'ult-terminal.debug'
      onExit(if code == 0 then 'status-success' else 'status-error')
    @program.on 'error', (err) =>
      console.log 'error', err if atom.config.get 'ult-terminal.debug'
      onExit 'status-error'
    @program.stdout.on 'data', =>
      @statusIcon.classList.remove 'status-error'
      @flashStatusIconClass 'status-info'
    @program.stderr.on 'data', =>
      console.log 'stderr' if atom.config.get 'ult-terminal.debug'
      @statusIcon.classList.add 'status-error'

  addCommandHistoryEntry: (command) ->
    return if command[0] == ' '
    limit = atom.config.get 'ult-terminal.commandHistorySize'
    for commandHistory in [@commandHistory, @statusView.state.commandHistory]
      commandHistory.push command if commandHistory[-1..][0] != command
      commandHistory[...commandHistory.length - limit] = [] if commandHistory.length > limit
    null
