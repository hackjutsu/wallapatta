Mod.require 'Weya.Base',
 'Weya'
 (Base, Weya) ->

  class App extends Base
   @initialize ->
    @elems = {}
    @_loading = true

    window.requestAnimationFrame =>
     @render()
     @loadRetainedDirectory =>
      @loadRetainedFile =>
       window.requestAnimationFrame =>
        @loadSavedContent =>
         @_loading = false

   loadRetainedDirectory: (callback) ->
    chrome.storage.local.get 'directory', (directory) =>
     directory = directory?.directory
     if directory?
      chrome.fileSystem.isRestorable directory, (isRestorable) =>
       if isRestorable
        chrome.fileSystem.restoreEntry directory, (d) =>
         if d? and d.isDirectory
          @on.openDirectory d
         callback()
       else
        callback()
     else
      callback()

   loadRetainedFile: (callback) ->
    chrome.storage.local.get 'file', (file) =>
     file = file?.file
     if file?
      chrome.fileSystem.isRestorable file, (isRestorable) =>
       if isRestorable
        console.info "Restoring #{file}"
        chrome.fileSystem.restoreEntry file, (d) =>
         if d? and d.isFile
          @on.openFile d, callback
       else
        callback()
     else
      callback()

   saveContent: (value, callback) ->
    return if @_loading
    chrome.storage.local.set content: value, ->
     callback?()

   loadSavedContent: (callback) ->
    chrome.storage.local.get 'content', (value) =>
     console.log 'read content'
     if value?.content?
      @send 'setText', content: value.content, saved: false

     callback()

   send: (method, data) ->
    data.method = method
    @sandbox.postMessage data, '*'

   @listen 'error', (e) ->
    console.error e

   @listen 'change', (data) ->
    @saveContent data.content

   render: ->
    @elems.sandbox = document.getElementById 'sandbox'
    @elems.sandbox.style.width = "#{window.innerWidth}px"
    @elems.sandbox.style.height = "#{window.innerHeight - 25}px"
    @elems.toolbar = document.getElementById 'toolbar'
    @elems.toolbar.innerHTML = ''
    Weya elem: @elems.toolbar, context: this, ->
     @span ->
      @$.elems.folder = @i ".fa.fa-lg.fa-folder",
       title: 'Select images folder'
       on: {click: @$.on.folder}
      @$.elems.open = @i ".fa.fa-lg.fa-upload",
       title: 'Open file'
       on: {click: @$.on.file}

     @$.elems.save = @span ->
      @i ".fa.fa-lg.fa-download",
       title: 'Save file'
       on: {click: @$.on.save}

     @i ".fa.fa-lg.fa-save",
      title: 'Save as'
      on: {click: @$.on.saveAs}

     @i ".fa.fa-lg.fa-print",
      title: 'Print'
      on: {click: @$.on.print}

     @$.elems.saveName = @span ".file-name", ""

    @elems.save.style.display = 'none'

    @sandbox = @elems.sandbox.contentWindow
    window.addEventListener 'resize', @on.resize

   @listen 'resize', ->
    @elems.sandbox.style.width = "#{window.innerWidth}px"
    @elems.sandbox.style.height = "#{window.innerHeight - 25}px"

   @listen 'print', ->
    @send 'print', {}

   @listen 'save', (e) ->
    return unless @file?
    @send 'save', {}

   @listen 'saveFileContent', (data) ->
    @contentWriting = data.content
    @file.createWriter @on.writer, @on.error

   @listen 'writeEnd', (e) ->
    console.log 'write end', e
    if @contentWriting?
     @content = @contentWriting
     @contentWriting = null

   @listen 'writer', (writer) ->
    writer.onerror = @on.error
    writer.onwriteend = @on.writeEnd

    blob = new Blob [@contentWriting], type: 'text/plain'

    writer.truncate blob.size
    @waitForIO writer, ->
     writer.seek 0
     writer.write blob

   waitForIO: (writer, callback) ->
    start = Date.now()
    reentrant = ->
     if writer.readyState is writer.WRITING and Date.now() - start < 4000
      setTimeout reentrant, 100

     if writer.readyState is writer.WRITING
       console.error "Write operation taking too long, aborting!
          (current writer readyState is #{writer.readyState})"
       writer.abort()
     else
      callback()

    setTimeout reentrant, 100

   @listen 'openDirectory', (entry) ->
    return unless entry?

    chrome.storage.local.set
     directory: chrome.fileSystem.retainEntry entry

    @loadDirEntry entry

   @listen 'file', (e) ->
    chrome.fileSystem.chooseEntry
     type: 'openFile'
     @on.openFile

   @listen 'saveAs', (e) ->
    chrome.fileSystem.chooseEntry
     type: 'saveFile'
     @on.saveAsFile

   @listen 'saveAsFile', (entry) ->
    return unless entry?

    chrome.storage.local.set
     file: chrome.fileSystem.retainEntry entry

    @elems.save.style.display = 'inline-block'
    @elems.saveName.textContent = entry.name
    @file = entry
    @send 'save', {}

   @listen 'fileChanged', (data) ->
    return unless @file?
    if data.changed
     @elems.saveName.textContent = "#{@file.name} *"
    else
     @elems.saveName.textContent = "#{@file.name}"

   @listen 'openFile', (entry, callback) ->
    return unless entry?

    chrome.storage.local.set
     file: chrome.fileSystem.retainEntry entry

    @elems.save.style.display = 'inline-block'
    @elems.saveName.textContent = entry.name
    @file = entry
    self = this
    entry.file (file) =>
     reader = new FileReader()

     reader.onerror = @on.error
     reader.onload = (e) ->
      self.send 'setText', content: e.target.result, saved: true
      callback?()

     reader.readAsText file

   @listen 'folder', (e) ->
    chrome.fileSystem.chooseEntry type: 'openDirectory', @on.openDirectory

   addResource: (entry) ->
    entry.file (file) =>
     reader = new FileReader()
     reader.onload = (e) =>
      @send 'addResource', dataURL: reader.result, path: entry.fullPath
      reader.result = null

     reader.readAsDataURL file

   loadDirEntry: (entry, callback) ->
    return unless entry.isDirectory
    console.log entry.fullPath
    reader = entry.createReader()
    self = this
    dirs = []

    readEntries = ->
     reader.readEntries onRead, self.on.error

    onRead = (results) ->
     if results.length is 0
      for e in dirs
       self.loadDirEntry e
      dirs = []
      return

     for e in results
      if e.isDirectory
       dirs.push e
      else
       self.addResource e
      readEntries()

    readEntries()

  APP = new App()

  MESSAGE_HANDLER = (e) ->
   APP.on[e.data.method] e.data, e

  window.addEventListener 'message', MESSAGE_HANDLER


document.addEventListener 'DOMContentLoaded', ->
 Mod.set 'Weya', Weya
 Mod.set 'Weya.Base', Weya.Base

 Mod.initialize()
