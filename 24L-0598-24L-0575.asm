;24L-0598 & 24L-0575
[org 0x100]


; bit blaze - top-down racing (mode 13h)
; sprite width auto-detect to avoid splitting; explicit labels (no dots)


; gfx mode
SCR_WIDTH   equ 320
SCR_HEIGHT  equ 200
VIDSEG      equ 0A000h

; road layout
ROADL       equ 60
ROADR       equ 260
BORDERW     equ 8

; spacing
NEARX       equ 40
NEARY       equ 20

; colors
COL_ASPHALT    equ 8
COL_LANEYELLOW equ 14
COL_BORDER     equ 7
COL_LIGHTGREEN equ 10
COL_DARKGREEN  equ 2


; code

start:
    mov ax, 0013h
    int 10h

    push cs
    pop ds
    mov ax, VIDSEG
    mov es, ax

    ; lanes
    mov ax, ROADR
    sub ax, ROADL
    inc ax
    mov bl, 3
    div bl
    xor bh, bh
    mov bl, al

    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    mov [lane1], ax

    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    add ax, dx
    mov [lane2], ax

    call draw_background

    ; seed rng
    mov ah, 00h
    int 1Ah
    xor bx, bx
    add bx, cx
    add bx, dx
    call randstep

    ; center red car between lane1 & lane2
    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1

    ; clamp and convert to left edge using CARHALFW (set later)
    cmp ax, CARHALFW
    ja  start_ok_left
    mov ax, CARHALFW
start_ok_left:
    cmp ax, SCR_WIDTH - CARHALFW
    jbe start_ok_right
    mov ax, SCR_WIDTH - CARHALFW
start_ok_right:
    sub ax, CARHALFW
    mov cx, ax

    ; y = min(160, SCR_HEIGHT - CARH - 1)
    mov ax, SCR_HEIGHT
    sub ax, CARH
    dec ax
    cmp ax, 160
    jae start_use160
    mov dx, ax
    jmp short start_y_set
start_use160:
    mov dx, 160
start_y_set:
    mov [redx], cx
    mov [redy], dx
    call draw_car_red

    ; spawn range for blue
    mov ax, ROADL
    add ax, BORDERW
    mov [colstart], ax

    mov ax, ROADR
    sub ax, BORDERW
    mov si, ax
    mov ax, CARW
    dec ax
    sub si, ax
    mov [colend], si

    mov bx, [colend]
    sub bx, [colstart]
    inc bx
    mov [colspan], bx

    mov ax, 10
    mov [rowmin], ax

    mov ax, SCR_HEIGHT
    sub ax, CARH
    sub ax, 10
    mov [rowmax], ax

    mov bx, [rowmax]
    sub bx, [rowmin]
    inc bx
    mov [rowspan], bx

retry_col:
    mov bx, [colspan]
    call getrandom
    add ax, [colstart]
    mov cx, ax

retry_row:
    mov bx, [rowspan]
    call getrandom
    add ax, [rowmin]
    mov dx, ax

    mov ax, cx
    sub ax, [redx]
    jns retry_x_ok
    neg ax
retry_x_ok:
    cmp ax, NEARX
    jb retry_col

    mov ax, dx
    sub ax, [redy]
    jns retry_y_ok
    neg ax
retry_y_ok:
    cmp ax, NEARY
    jb retry_row

    call draw_car_blue

    ; hide cursor
    mov ah, 02h
    xor bh, bh
    mov dh, 24
    xor dl, dl
    int 10h

    ; wait key
    xor ah, ah
    int 16h

    ; back to text
    mov ax, 0003h
    int 10h

    mov ax, 4C00h
    int 21h


; background

draw_background:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    xor di, di
    xor bx, bx
    xor bp, bp

bg_row_loop:
    mov cx, SCR_WIDTH
    xor si, si

bg_col_loop:
    mov ax, si
    cmp ax, ROADL
    jb bg_outside_grass_jump
    cmp ax, ROADR
    ja bg_outside_grass_jump

    ; inside road
    mov ax, si
    sub ax, ROADL
    cmp ax, BORDERW
    jb  bg_paint_border
    mov ax, ROADR
    sub ax, si
    cmp ax, BORDERW
    jb  bg_paint_border

    ; default asphalt before lane logic (prevents stale AL)
    mov al, COL_ASPHALT

    ; dashed lane marks
    mov dx, si
    cmp dx, [lane1]
    je  bg_maybe_dash
    cmp dx, [lane2]
    je  bg_maybe_dash
    jmp short bg_write_pixel

bg_paint_border:
    mov al, COL_BORDER
    jmp short bg_write_pixel

bg_maybe_dash:
    ; dash every 4th scanline; otherwise asphalt
    test bp, 3
    jnz short bg_write_pixel
    mov al, COL_LANEYELLOW
    jmp short bg_write_pixel

bg_outside_grass_jump:
    ; LCG for grass mix
    mov ax, bx
    shl bx, 5
    add bx, ax
    add bx, 7
    mov dl, bl
    and dl, 3
    cmp dl, 0
    je bg_grass1
    cmp dl, 1
    je bg_grass2
    mov al, COL_DARKGREEN
    jmp short bg_write_pixel
bg_grass2:
    mov al, COL_LIGHTGREEN
    jmp short bg_write_pixel
bg_grass1:
    mov al, COL_DARKGREEN

bg_write_pixel:
    mov [es:di], al
    inc di
    inc si
    loop bg_col_loop

    inc bp
    cmp di, SCR_WIDTH*SCR_HEIGHT
    jb bg_row_loop

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw red car (cx=x, dx=y)
draw_car_red:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, dx
    mov bx, 320
    mul bx
    mov di, ax
    add di, cx

    mov si, car_sprite
    mov cx, CARH

draw_red_row:
    push cx
    push di
    mov cx, CARW
draw_red_col:
    lodsb
    or  al, al
    jz  draw_red_skip
    mov [es:di], al
draw_red_skip:
    inc di
    loop draw_red_col
    pop di
    add di, SCR_WIDTH
    pop cx
    loop draw_red_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw blue car (cx=x, dx=y) — recolor-from-red-on-copy

draw_car_blue:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, dx
    mov bx, 320
    mul bx
    mov di, ax
    add di, cx

    mov si, car_blue_sprite      ; same bytes as red
    mov cx, CARH

draw_blue_row:
    push cx
    push di
    mov cx, CARW
draw_blue_col:
    lodsb
    or  al, al
    jz  draw_blue_skip

    ; recolor common red shades -> blues
    cmp al, 12          ; light red
    jne .chk_red
    mov al, 9           ; light blue
    jmp short .store
.chk_red:
    cmp al, 4           ; red
    jne .chk_dark
    mov al, 1           ; blue
    jmp short .store
.chk_dark:
    cmp al, 3           ; dark-ish body?
    jne .store
    mov al, 1
.store:
    mov [es:di], al
draw_blue_skip:
    inc di
    loop draw_blue_col
    pop di
    add di, SCR_WIDTH
    pop cx
    loop draw_blue_row

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; rng
randstep:
    mov ax, bx
    shl bx, 5
    add bx, ax
    add bx, 7
    mov ax, bx
    ret

getrandom:
    push dx
    push cx
    mov ah, 00h
    int 1Ah
    mov ax, dx
    xor dx, dx
    div bx
    mov ax, dx
    pop cx
    pop dx
    ret

; sprite include — must define: car_sprite
%include "car_red.inc"
car_sprite_end:

; also bring in blue (alias -> same bytes)
%include "car_blue.inc"

; sprite size auto-detect
sprite_bytes  equ car_sprite_end - car_sprite

%assign _carw 0
%macro tryw 1
%if _carw = 0
 %if (sprite_bytes %% %1) = 0
  %assign _carw %1
 %endif
%endif
%endmacro

tryw 64
tryw 60
tryw 56
tryw 50
tryw 48
tryw 45
tryw 40
tryw 32

%if _carw = 0
 %error "could not infer CARW from sprite size — set it manually"
%endif

CARW        equ _carw
CARH        equ sprite_bytes / CARW
CARHALFW    equ (CARW/2)

; data
lane1      dw 0
lane2      dw 0
redx       dw 0
redy       dw 0
colspan    dw 0
rowspan    dw 0
colstart   dw 0
colend     dw 0
rowmin     dw 0
rowmax     dw 0

; car_blue.inc
; provides: car_blue_sprite (alias to red sprite data)
; draw_car_blue recolors at copy time so sizes stay identical
car_blue_sprite     equ car_sprite
car_blue_sprite_end equ car_sprite_end