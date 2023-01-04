" Use Vim settings, rather than Vi settings (much better!).
set nocompatible

" In many terminal emulators the mouse works just fine, thus enable it.
if has('mouse')
  set mouse=a
endif

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
  syntax on
  " set hlsearch
endif

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

set history=500		" keep 50 lines of command line history
set ruler		" show the cursor position all the time
set showcmd		" display incomplete commands
set incsearch		" do incremental searching
set number

" Don't use Ex mode, use Q for formatting
map Q gq

" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
inoremap <C-U> <C-G>u<C-U>

" Set colorscheme
" Builtin colorscheme can be one of below:
"  blue, darkblue, default, delek
"  desert, elflord, evening, industry
"  koehler, morning, murphy, pablo
"  peachpuff, ron, shine, slate
"  torte, zellner
colorscheme elflord

" Some key binds
inoremap jk <esc>

" configure expanding of tabs for various file types
autocmd BufRead,BufNewFile *.py set expandtab
autocmd BufRead,BufNewFile *.c set expandtab
autocmd BufRead,BufNewFile *.h set expandtab
autocmd BufRead,BufNewFile Makefile* set noexpandtab

" configure editor with tabs and nice stuff...
set expandtab           " enter spaces when tab is pressed
set textwidth=120       " break lines when line length increases
set tabstop=4           " use 4 spaces to represent tab
set softtabstop=4
set shiftwidth=4        " number of spaces to use for auto indent
set autoindent          " copy indent from current line when starting a new line
