let s:config     = ctrlspace#context#Configuration()
let s:modes      = ctrlspace#modes#Modes()
let s:allBuffers = {}

function! ctrlspace#buffers#SelectedBufferName()
    return s:modes.Buffer.Enabled ? bufname(ctrlspace#window#SelectedIndex()) : ""
endfunction

function! ctrlspace#buffers#Init()
    for current in range(1, bufnr("$"))
        if !getbufvar(current, "&modifiable") || !getbufvar(current, "&buflisted") || getbufvar(current, "&ft") ==? "ctrlspace"
            break
        endif

        if !has_key(s:allBuffers, current)
            let s:allBuffers[current] = len(s:allBuffers) + 1
        endif
    endfor
endfunction

function! ctrlspace#buffers#AddBuffer()
    let current = bufnr('%')

    if !getbufvar(current, "&modifiable") || !getbufvar(current, "&buflisted") || getbufvar(current, "&ft") ==? "ctrlspace"
        return
    endif

    if !has_key(s:allBuffers, current)
        let s:allBuffers[current] = len(s:allBuffers) + 1
    endif

    if s:modes.Zoom.Enabled
        return
    endif

    let b:CtrlSpaceJumpCounter = ctrlspace#jumps#IncrementJumpCounter()

    if !exists("t:CtrlSpaceList")
        let t:CtrlSpaceList = {}
    endif

    if !has_key(t:CtrlSpaceList, current)
        let t:CtrlSpaceList[current] = len(t:CtrlSpaceList) + 1
    endif
endfunction

function! ctrlspace#buffers#Buffers(tabnr)
    if a:tabnr
        let buffers = gettabvar(a:tabnr, "CtrlSpaceList")
        if type(buffers) != type({})
            return {}
        endif
    else
        let buffers = s:allBuffers
    endif

    return filter(buffers, "buflisted(str2nr(v:key))") " modify proper dictionary and return it
endfunction

function! ctrlspace#buffers#LoadBuffer(...)
    let nr = ctrlspace#window#SelectedIndex()
    call ctrlspace#window#Kill(0, 1)

    let commands = len(a:000)

    if commands > 0
        silent! exe ":" . a:1
    endif

    silent! exe ":b " . nr

    if commands > 1
        silent! exe ":" . a:2
    endif
endfunction

function! ctrlspace#buffers#LoadManyBuffers(...)
    let nr    = ctrlspace#window#SelectedIndex()
    let curln = line(".")

    call ctrlspace#window#Kill(0, 0)
    call ctrlspace#window#GoToStartWindow()

    let commands = len(a:000)

    if commands > 0
        silent! exe ":" . a:1
    endif

    exec ":b " . nr
    normal! zb

    if commands > 1
        silent! exe ":" . a:2
    endif

    call ctrlspace#window#Toggle(1)
    call ctrlspace#window#MoveSelectionBar(curln)
endfunction

function! ctrlspace#buffers#ZoomBuffer(nr, ...)
    if !s:modes.Zoom.Enabled
        call s:modes.Zoom.Enable()
        call s:modes.Zoom.SetData("OriginalBuffer", winbufnr(t:CtrlSpaceStartWindow))
    endif

    let nr = a:nr ? a:nr : ctrlspace#window#SelectedIndex()

    call ctrlspace#window#Kill(0, 0)
    call ctrlspace#window#GoToStartWindow()

    silent! exe ":b " . nr

    let customCommands = !empty(a:000) ? a:1 : ["normal! zb"]

    for c in customCommands
        silent! exe c
    endfor

    call ctrlspace#window#Toggle(1)
endfunction

function! ctrlspace#buffers#CopyBufferToTab(tab)
    return s:copyOrMoveSelectedBufferIntoTab(tab, 0)
endfunction

function! ctrlspace#buffers#MoveBufferToTabl(tab)
    return s:copyOrMoveSelectedBufferIntoTab(tab, 1)
endfunction

" Detach a buffer if it belongs to other tabs or delete it otherwise.
" It means, this function doesn't leave buffers without tabs.
function! ctrlspace#buffers#CloseBuffer()
    let nr = ctrlspace#window#SelectedIndex()
    let foundTabs = 0

    for t in range(1, tabpagenr('$'))
        let cslist = gettabvar(t, "CtrlSpaceList")
        if !empty(cslist) && exists("cslist[nr]")
            let foundTabs += 1
        endif
    endfor

    if foundTabs > 1
        call ctrlspace#buffers#DetachBuffer()
    else
        call ctrlspace#buffers#DeleteBuffer()
    endif
endfunction

" deletes the selected buffer
function! ctrlspace#buffers#DeleteBuffer()
    let nr = ctrlspace#window#SelectedIndex()
    let modified = getbufvar(str2nr(nr), "&modified")

    if modified && !ctrlspace#ui#Confirmed("The buffer contains unsaved changes. Proceed anyway?")
        return
    endif

    let selBufWin = bufwinnr(str2nr(nr))
    let curln     = line(".")

    if selBufWin != -1
        call ctrlspace#window#MoveSelectionBar("down")
        if ctrlspace#window#SelectedIndex() == nr
            call ctrlspace#window#MoveSelectionBar("up")

            if ctrlspace#window#SelectedIndex() == nr
                if bufexists(nr) && (!empty(getbufvar(nr, "&buftype")) || filereadable(bufname(nr)) || modified)
                    let curln = line(".")
                    call ctrlspace#window#Kill(0, 0)
                    silent! exe selBufWin . "wincmd w"
                    enew
                else
                    return
                endif
            else
                call s:loadBufferIntoWindow(selBufWin)
            endif
        else
            call s:loadBufferIntoWindow(selBufWin)
        endif
    else
        let curln = line(".")
        call ctrlspace#window#Kill(0, 0)
    endif

    let curtab = tabpagenr()

    for t in range(1, tabpagenr('$'))
        if t == curtab
            continue
        endif

        for b in tabpagebuflist(t)
            if b == nr
                silent! exe "tabn " . t

                let tabWin = bufwinnr(b)
                let cslist = copy(gettabvar(t, "CtrlSpaceList"))

                call remove(cslist, nr)

                call settabvar(t, "CtrlSpaceList", cslist)

                silent! exe tabWin . "wincmd w"

                if !empty(cslist)
                    silent! exe "b" . keys(cslist)[0]
                else
                    enew
                endif
            endif
        endfor
    endfor

    silent! exe "tabn " . curtab
    silent! exe "bdelete! " . nr

    call s:forgetBuffersInAllTabs([nr])
    call ctrlspace#window#Toggle(1)
    call ctrlspace#window#MoveSelectionBar(curln)
endfunction

function! ctrlspace#buffers#DetachBuffer()
    let nr = ctrlspace#window#SelectedIndex()

    if exists("t:CtrlSpaceList[nr]")
        let selBufWin = bufwinnr(nr)

        if selBufWin != -1
            call ctrlspace#window#MoveSelectionBar("down")
            if ctrlspace#window#SelectedIndex() == nr
                call ctrlspace#window#MoveSelectionBar("up")

                if ctrlspace#window#SelectedIndex() == nr
                    if bufexists(nr) && (!empty(getbufvar(nr, "&buftype")) || filereadable(bufname(nr)))
                        call ctrlspace#window#Kill(0, 0)
                        silent! exe selBufWin . "wincmd w"
                        enew
                    else
                        return
                    endif
                else
                    call s:loadBufferIntoWindow(selBufWin)
                endif
            else
                call s:loadBufferIntoWindow(selBufWin)
            endif
        else
            call ctrlspace#window#Kill(0, 0)
        endif
        call remove(t:CtrlSpaceList, nr)
        call ctrlspace#window#Toggle(1)
    endif

    return nr
endfunction

function! ctrlspace#buffers#GoToBufferOrFile(direction)
    let nr      = ctrlspace#window#SelectedIndex()
    let curTab  = tabpagenr()
    let lastTab = tabpagenr("$")

    let targetTab = 0
    let targetBuf = 0

    if lastTab == 1
        let tabsToCheck = [1]
    elseif curTab == 1
        if a:direction == "next"
            let tabsToCheck = range(2, lastTab) + [1]
        else
            let tabsToCheck = range(lastTab, curTab, -1)
        endif
    elseif curTab == lastTab
        if a:direction == "next"
            let tabsToCheck = range(1, lastTab)
        else
            let tabsToCheck = range(lastTab - 1, 1, -1) + [lastTab]
        endif
    else
        if a:direction == "next"
            let tabsToCheck = range(curTab + 1, lastTab) + range(1, curTab - 1) + [curTab]
        else
            let tabsToCheck = range(curTab - 1, 1, -1) + range(lastTab, curTab + 1, -1) + [curTab]
        endif
    endif

    if s:modes.File.Enabled
        let file = fnamemodify(ctrlspace#files#SelectedFileName(), ":p")
    endif

    for t in tabsToCheck
        for [bufnr, name] in items(ctrlspace#api#Buffers(t))
            if s:modes.File.Enabled
                if fnamemodify(name, ":p") !=# file
                    continue
                endif
            elseif str2nr(bufnr) != nr
                continue
            endif

            let targetTab = t
            let targetBuf = str2nr(bufnr)
            break
        endfor

        if targetTab > 0
            break
        endif
    endfor

    if (targetTab > 0) && (targetBuf > 0)
        call ctrlspace#window#Kill(0, 1)
        silent! exe "normal! " . targetTab . "gt"
        call ctrlspace#window#Toggle(0)
        for i in range(b:size)
            if b:indices[i] == targetBuf
                call ctrlspace#window#MoveSelectionBar(i + 1)
                break
            endif
        endfor
    else
        call ctrlspace#ui#Msg("Cannot find a tab containing selected " . (s:modes.File.Enabled ? "file" : "buffer"))
    endif
endfunction

function! ctrlspace#buffers#CollectUnsavedBuffers()
    let buffers = []

    for i in range(1, bufnr("$"))
        if getbufvar(i, "&modified") && getbufvar(i, "&modifiable") && getbufvar(i, "&buflisted")
            call add(buffers, i)
        endif
    endfor

    if empty(buffers)
        return 0
    endif

    call ctrlspace#window#Kill(0, 1)

    tabnew

    call ctrlspace#tabs#SetTabLabel(tabpagenr(), "Unsaved buffers", 1)

    for b in buffers
        silent! exe ":b " . b
    endfor

    call ctrlspace#window#Toggle(0)
    return 1
endfunction

function! ctrlspace#buffers#DeleteHiddenNonameBuffers(internal)
    let keep = {}

    " keep visible ones
    for t in range(1, tabpagenr("$"))
        for b in tabpagebuflist(t)
            let keep[b] = 1
        endfor
    endfor

    " keep all but nonames
    for b in range(1, bufnr("$"))
        if bufexists(b) && (!empty(getbufvar(b, "&buftype")) || filereadable(bufname(b)))
            let keep[b] = 1
        endif
    endfor

    if !a:internal
        call ctrlspace#window#Kill(0, 0)
    endif

    let removed = s:keepBuffersForKeys(keep)

    if !empty(removed)
        call s:forgetBuffersInAllTabs(removed)
    endif

    if !a:internal
        call ctrlspace#window#Toggle(1)
    endif
endfunction

" deletes all foreign buffers
function! ctrlspace#buffers#DeleteForeignBuffers(internal)
    let buffers = {}

    for t in range(1, tabpagenr("$"))
        silent! call extend(buffers, gettabvar(t, "CtrlSpaceList"))
    endfor

    if !a:internal
        call ctrlspace#window#Kill(0, 0)
    endif

    call s:keepBuffersForKeys(buffers)

    if !a:internal
        call ctrlspace#window#Toggle(1)
    endif
endfunction

function! s:copyOrMoveSelectedBufferIntoTab(tab, move)
    let nr = ctrlspace#window#SelectedIndex()

    if !getbufvar(str2nr(nr), "&modifiable") || !getbufvar(str2nr(nr), "&buflisted") || empty(bufname(str2nr(nr)))
        return
    endif

    let map = gettabvar(a:tab, "CtrlSpaceList")

    if a:move
        call ctrlspace#buffers#DetachBuffer()
    endif

    if empty(map)
        let newMap = {}
        let newMap[nr] = 1
        call settabvar(a:tab, "CtrlSpaceList", newMap)
    elseif !exists("map[nr]")
        let map[nr] = len(map) + 1
    endif

    call ctrlspace#window#Kill(0, 1)

    silent! exe "normal! " . a:tab . "gt"

    call ctrlspace#window#Toggle(0)

    let bname = bufname(str2nr(nr))

    for i in range(b:size)
        if bufname(b:indices[i]) ==# bname
            call ctrlspace#windowMoveSelectionBar(i + 1)
            call ctrlspace#buffers#LoadManyBuffers()
            break
        endif
    endfor
endfunction

function! s:keepBuffersForKeys(dict)
    let removed = []

    for b in range(1, bufnr("$"))
        if buflisted(b) && !has_key(a:dict, b) && !getbufvar(b, "&modified")
            exe "bwipeout" b
            call add(removed, b)
        endif
    endfor

    return removed
endfunction

function! s:loadBufferIntoWindow(winnr)
    let old = t:CtrlSpaceStartWindow
    let t:CtrlSpaceStartWindow = a:winnr
    call ctrlspace#buffers#LoadBuffer()
    let t:CtrlSpaceStartWindow = old
endfunction

function! s:forgetBuffersInAllTabs(numbers)
    for t in range(1, tabpagenr("$"))
        let cslist = copy(gettabvar(t, "CtrlSpaceList"))

        if empty(cslist)
            continue
        endif

        for nr in a:numbers
            if exists("CtrlSpaceList[nr]")
                call remove(cslist, nr)
            endif
        endfor

        call settabvar(t, "CtrlSpaceList", cslist)
    endfor
endfunction
