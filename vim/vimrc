" Use Vim settings, rather than Vi settings (much better!).
set nocompatible

" In many terminal emulators the mouse works just fine, thus enable it.
"if has('mouse')
"  set mouse=a
"endif

" Switch syntax highlighting on, when the terminal has colors
" Also switch on highlighting the last used search pattern.
if &t_Co > 2 || has("gui_running")
  syntax on
  " set hlsearch
endif

" allow backspacing over everything in insert mode
set backspace=indent,eol,start

set history=50		" keep 50 lines of command line history
set ruler		" show the cursor position all the time
set showcmd		" display incomplete commands
set incsearch		" do incremental searching
set number

" Don't use Ex mode, use Q for formatting
map Q gq

" CTRL-U in insert mode deletes a lot.  Use CTRL-G u to first break undo,
" so that you can undo CTRL-U after inserting a line break.
inoremap <C-U> <C-G>u<C-U>

" Set Auto Indent and Tab Width
set autoindent
set tabstop=8
set softtabstop=4
set shiftwidth=4
set noexpandtab

" Set colorscheme
" Builtin colorscheme can be one of below:
"  blue, darkblue, default, delek
"  desert, elflord, evening, industry
"  koehler, morning, murphy, pablo
"  peachpuff, ron, shine, slate
"  torte, zellner
colorscheme delek

" Some key binds
inoremap jk <esc>


