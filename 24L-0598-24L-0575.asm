;24L-0598 & 24L-0575
[org 0x0100]

;bit blazer race game

SCR_WIDTH   equ 320
SCR_HEIGHT  equ 200
VIDSEG      equ 0A000h

ROADL       equ 60
ROADR       equ 260
BORDERW     equ 8

NEARX       equ 40
NEARY       equ 20

COL_ASPHALT    equ 8
COL_LANEYELLOW equ 14
COL_BORDER     equ 7

; coin sprite (from coin.inc: width=20, height=20, 0 = transparent)
COINW       equ 20
COINH       equ 20
COIN_HALFW  equ COINW/2
COIN_HALFH  equ COINH/2
COIN_HALF   equ COIN_HALFH

; collision box around coin center (20x20 square)
COIN_COLL_HALF equ COINW/2
COIN_COLL_SIZE equ COIN_COLL_HALF*2

SCROLL_SPEED       equ 12
COIN_SCROLL        equ 12
MIN_SPAWN_DELAY    equ 12
MAX_SPAWN_DELAY    equ 30
COIN_RESPAWN_DELAY equ 40

MAX_BLUE_CARS equ 5

REASON_NONE  equ 0
REASON_QUIT  equ 1
REASON_FUEL  equ 2
REASON_CRASH equ 3

; fuel tank sprite (from fueltank.inc: width=17, height=20, -1 = transparent)
FUELW        equ 17
FUELH        equ 20
FUEL_HALFW   equ FUELW/2        ; 8
FUEL_HALFH   equ FUELH/2        ; 10

; collision box around fuel center (square)
FUEL_COLL_HALF  equ FUELW/2
FUEL_COLL_SIZE  equ FUEL_COLL_HALF*2

; fuel movement / spawn settings
FUEL_SCROLL        equ 12        ; same as coin scroll
FUEL_RESPAWN_DELAY equ 120       ; normal delay
FUEL_RESPAWN_LOW   equ 40        ; faster when fuel is low
FUEL_LOW_THRESHOLD equ 5         ; "low fuel" if <= 5
FUEL_GAIN          equ 5         ; fuel gained per pickup
FUEL_MAX equ 12


; start game
start:
    mov ax, 13h
    int 10h

    push cs
    pop ds
    mov ax, VIDSEG
    mov es, ax

    mov byte [end_reason], REASON_NONE

    ; lane width = (ROADR - ROADL + 1) / 3
    mov ax, ROADR
    sub ax, ROADL
    inc ax
    mov bl, 3
    div bl
    xor bh, bh
    mov bl, al

    ; lane1 = ROADL + laneWidth
    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    mov [lane1], ax

    ; lane2 = ROADL + 2*laneWidth
    mov ax, ROADL
    mov dl, bl
    xor dh, dh
    add ax, dx
    add ax, dx
    mov [lane2], ax

    ; calculate lane centers
    mov ax, ROADL
    add ax, [lane1]
    shr ax, 1
    mov [lanec1], ax

    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1
    mov [lanec2], ax

    mov ax, [lane2]
    add ax, ROADR
    shr ax, 1
    mov [lanec3], ax

    ; safe x min / max for centers
    mov ax, ROADL
    add ax, BORDERW
    add ax, CARHALFW
    mov [xminc], ax

    mov ax, ROADR
    sub ax, BORDERW
    sub ax, CARHALFW
    mov [xmaxc], ax

    ; clamp lanec1
    mov ax, [lanec1]
    cmp ax, [xminc]
    jae lane1_min_ok
    mov ax, [xminc]
lane1_min_ok:
    cmp ax, [xmaxc]
    jbe lane1_max_ok
    mov ax, [xmaxc]
lane1_max_ok:
    mov [lanec1], ax

    ; clamp lanec2
    mov ax, [lanec2]
    cmp ax, [xminc]
    jae lane2_min_ok
    mov ax, [xminc]
lane2_min_ok:
    cmp ax, [xmaxc]
    jbe lane2_max_ok
    mov ax, [xmaxc]
lane2_max_ok:
    mov [lanec2], ax

    ; clamp lanec3
    mov ax, [lanec3]
    cmp ax, [xminc]
    jae lane3_min_ok
    mov ax, [xminc]
lane3_min_ok:
    cmp ax, [xmaxc]
    jbe lane3_max_ok
    mov ax, [xmaxc]
lane3_max_ok:
    mov [lanec3], ax

    ; center red car horizontally between lane1 and lane2
    mov ax, [lane1]
    add ax, [lane2]
    shr ax, 1

    cmp ax, CARHALFW
    ja near red_left_ok
    mov ax, CARHALFW
red_left_ok:
    cmp ax, SCR_WIDTH - CARHALFW
    jbe near red_right_ok
    mov ax, SCR_WIDTH - CARHALFW
red_right_ok:
    sub ax, CARHALFW
    mov [redx], ax

    ; set red car Y
    mov ax, SCR_HEIGHT
    sub ax, CARH
    dec ax
    cmp ax, 160
    jae set_redy
    mov dx, ax
    jmp near set_redy_done
set_redy:
    mov dx, 160
set_redy_done:
    mov [redy], dx

    mov byte [red_lane], 1

    ; column safe range for blue cars
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

    ; initialize blue cars
    call init_blue_cars

    ; random spawn timer
    mov bx, MAX_SPAWN_DELAY - MIN_SPAWN_DELAY + 1
    call getrandom
    add ax, MIN_SPAWN_DELAY
    mov [spawn_timer], ax

    ; setup coins initially
    mov word [coin_active], 0
    mov word [coin_active+2], 0
    mov word [coin_active+4], 0

    mov ax, [lanec2]
    mov [coin_x+2], ax
    mov word [coin_y+2], 40
    mov word [coin_active+2], 1

    mov word [coin_spawn_timer], COIN_RESPAWN_DELAY
    mov word [game_over_flag], 0
    mov word [coin_count], 0
    mov word [fuel_value], 12

    ; setup fuel initially (all inactive, spawn timer started)
    mov word [fuel_active], 0
    mov word [fuel_active+2], 0
    mov word [fuel_active+4], 0
    mov word [fuel_spawn_timer], FUEL_RESPAWN_DELAY

    ; hide cursor
    mov ah, 01h
    mov ch, 32
    int 10h

    ; menu -> name/roll input -> tutorial -> static start screen
    call show_start_screen
    call show_player_info_screen
    call show_instruction_screen

    call draw_background

    ; force spawn a blue car at start screen
    mov si, 0
    call spawn_blue_car

    mov si, 0
    call get_blue_car_ptr
    mov word [bx + 4], 20
    mov ax, 20
    add ax, CARH
    mov [bx + 6], ax

    xor si, si
    call get_blue_car_ptr
    mov cx, [bx+2]
    mov dx, [bx+4]
    call draw_car_blue

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    call draw_fuel_hud
    call draw_coin_hud
    call draw_fuel_text

    ; static road screen with blinking S in "Press S to start"
    call show_press_to_start_overlay


game_loop:

    call erase_all_blue_cars
    call update_all_blue_cars
    call update_coins
    call update_fuel
    call draw_all_blue_cars

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

; reduce movement cooldown
    cmp word [move_cooldown], 0
    jle skip_cooldown_reduce
    dec word [move_cooldown]
    skip_cooldown_reduce:

    mov ah, 01h
    int 16h
    jz near no_key

    xor ah, ah
    int 16h

    cmp al, 27
    je key_escape

    cmp al, 0
    jne near no_key

    cmp ah, 4Bh
    je key_move_left_try

    cmp ah, 4Dh
    je key_move_right_try
	
    cmp ah, 48h
    je key_move_up_try

    cmp ah, 50h
    je key_move_down_try

    jmp no_key

key_escape:
    call confirm_exit
    cmp al, 1
    je key_escape_confirmed
    call redraw_full_scene
    jmp after_keys

key_escape_confirmed:
    mov word [game_over_flag], 1
    mov byte [end_reason], REASON_QUIT
    jmp game_over_mode

key_move_left_try:
    cmp word [move_cooldown], 0
    jne near after_keys       ; still cooling down → ignore key
    jmp key_move_left

key_move_right_try:
    cmp word [move_cooldown], 0
    jne near after_keys
    jmp key_move_right

key_move_up_try:
    cmp word [move_cooldown], 0
    jne near after_keys
    jmp key_move_up

key_move_down_try:
    cmp word [move_cooldown], 0
    jne near after_keys
    jmp key_move_down

key_move_left:
    ; check if changing into left lane would crash
    mov al, [red_lane]
    cmp al, 0
    je key_move_left_do_move      ; already leftmost lane, no side-lane change
    dec al                        ; target lane = current - 1
    call check_side_lane_collision
    cmp al, 1
    jne key_move_left_do_move

    ; lane-change collision: keep car in same lane, show sparks, end game
    call draw_spark
    mov cx, 30000
kml_spark_delay:
    loop kml_spark_delay

    mov word [game_over_flag], 1
    mov byte [end_reason], REASON_CRASH
    jmp game_over_mode

key_move_left_do_move:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_left
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    mov word [move_cooldown], 3   ; cooldown frames
    jmp near do_fuel_tick

key_move_right:
    ; check if changing into right lane would crash
    mov al, [red_lane]
    cmp al, 2
    je key_move_right_do_move     ; already rightmost lane
    inc al                        ; target lane = current + 1
    call check_side_lane_collision
    cmp al, 1
    jne key_move_right_do_move

    ; lane-change collision: keep car in same lane, show sparks, end game
    call draw_spark
    mov cx, 30000
kmr_spark_delay:
    loop kmr_spark_delay

    mov word [game_over_flag], 1
    mov byte [end_reason], REASON_CRASH
    jmp game_over_mode

key_move_right_do_move:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_right
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    mov word [move_cooldown], 3
    jmp near do_fuel_tick

key_move_up:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_up
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    mov word [move_cooldown], 3
    jmp near do_fuel_tick

key_move_down:
    mov cx, [redx]
    mov dx, [redy]
    call erase_car
    call move_red_down
    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red
    mov word [move_cooldown], 3
    jmp near do_fuel_tick

move_red_up:
    push ax

    mov ax, [redy]
    cmp ax, 20
    jle mru_no_move
    sub ax, 20
    mov [redy], ax

mru_no_move:
    pop ax
    ret

move_red_down:
    push ax

    mov ax, [redy]
    add ax, 20
    cmp ax, SCR_HEIGHT - CARH
    jge mrd_no_move
    mov [redy], ax
    jmp mrd_done

mrd_no_move:
    mov ax, SCR_HEIGHT - CARH
    mov [redy], ax

mrd_done:
    pop ax
    ret

no_key:
    jmp do_fuel_tick

; TIMER-BASED FUEL DROP (runs every frame)
do_fuel_tick:
    dec word [fuel_tick]
    jnz fuel_tick_done       ; not yet

    mov word [fuel_tick], 20 ; reset timer

    ; reduce fuel by 1
    cmp word [fuel_value], 0
    je fuel_empty_now_tick
    dec word [fuel_value]

    call draw_fuel_text
    call draw_fuel_hud

    cmp word [fuel_value], 0
    jne fuel_tick_done

fuel_empty_now_tick:
    mov word [game_over_flag], 1
    mov byte [end_reason], REASON_FUEL
    jmp game_over_mode

fuel_tick_done:

after_keys:
    call check_blue_collisions
    cmp word [game_over_flag], 0
    jne game_over_mode

    mov cx, 250
delay_outer:
    mov dx, 1000
delay_inner:
    dec dx
    jnz delay_inner
    loop delay_outer

    jmp game_loop

game_over_mode:
    call game_over_screen     ; just "GAME OVER, press any key"
    mov ah, 0
    int 16h

    call show_end_screen      ; summary screen with name/roll/reason
    cmp al, 1                 ; 1 = retry, 0 = exit
    je restart_game
    jmp near exit_to_dos

restart_game:
    jmp start

exit_to_dos:
    mov ax, 3
    int 10h
    mov ax, 4C00h
    int 21h


; initialize all blue cars as inactive
init_blue_cars:
    push ax
    push bx
    push cx
    push si
    
    xor si, si
init_blue_loop:
    call get_blue_car_ptr
    mov word [bx], 0
    mov word [bx + 2], 0
    mov word [bx + 4], 0FFFFh
    mov word [bx + 6], 0
    mov byte [bx + 8], 0
    mov word [bx + 10], 0
    mov word [bx + 12], 0FFFFh
    
    inc si
    cmp si, MAX_BLUE_CARS
    jb init_blue_loop
    
    pop si
    pop cx
    pop bx
    pop ax
    ret


; get pointer to blue car structure at index SI
; returns BX = pointer to structure
get_blue_car_ptr:
    push ax
    mov bx, si
    mov ax, 14
    mul bx
    mov bx, blue_cars
    add bx, ax
    pop ax
    ret


; erase all active blue cars using old positions
erase_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    
    xor si, si
erase_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx + 12]
    cmp ax, 0FFFFh
    je erase_skip
    cmp ax, SCR_HEIGHT
    jge erase_skip
    
    mov cx, [bx + 10]
    mov dx, [bx + 12]
    call erase_car
    
erase_skip:
    inc si
    cmp si, MAX_BLUE_CARS
    jb erase_all_loop
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw all active blue cars
draw_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    
    xor si, si
draw_blue_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx]
    cmp ax, 0
    je draw_blue_skip_car
    
    mov ax, [bx + 4]
    cmp ax, 0FFFFh
    je draw_blue_skip_car
    cmp ax, SCR_HEIGHT
    jge draw_blue_skip_car
    
    mov cx, [bx + 2]
    mov dx, [bx + 4]
    call draw_car_blue
    
draw_blue_skip_car:
    inc si
    cmp si, MAX_BLUE_CARS
    jb draw_blue_all_loop
    
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; update all blue cars (movement and spawning)
update_all_blue_cars:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    
    xor si, si
update_blue_all_loop:
    call get_blue_car_ptr
    
    mov ax, [bx]
    cmp ax, 0
    je blue_try_spawn
    
    mov ax, [bx + 2]
    mov [bx + 10], ax
    mov ax, [bx + 4]
    mov [bx + 12], ax
    
    mov ax, [bx + 4]
    add ax, SCROLL_SPEED
    mov [bx + 4], ax
    
    mov dx, ax
    add dx, CARH
    mov [bx + 6], dx
    
    cmp ax, SCR_HEIGHT
    jl update_blue_next
    
    mov word [bx], 0
    mov word [bx + 4], 0FFFFh
    jmp near update_blue_next
    
blue_try_spawn:
    dec word [spawn_timer]
    jnz update_blue_next

    push bx
    mov bx, MAX_SPAWN_DELAY - MIN_SPAWN_DELAY + 1
    call getrandom
    add ax, MIN_SPAWN_DELAY
    mov [spawn_timer], ax
    pop bx

    call find_inactive_car
    cmp si, 0FFFFh
    je update_blue_next

    call spawn_blue_car

update_blue_next:
    inc si
    cmp si, MAX_BLUE_CARS
    jb update_blue_all_loop
    
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; find first inactive blue car
; returns SI index or 0FFFFh if all active
find_inactive_car:
    push ax
    push bx
    push cx
    
    xor si, si
find_inactive_loop:
    call get_blue_car_ptr
    mov ax, [bx]
    cmp ax, 0
    je find_inactive_found
    
    inc si
    cmp si, MAX_BLUE_CARS
    jb find_inactive_loop
    
    mov si, 0FFFFh
    jmp find_inactive_done
    
find_inactive_found:
find_inactive_done:
    pop cx
    pop bx
    pop ax
    ret


; spawn a blue car at index SI
spawn_blue_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    call get_blue_car_ptr
    mov bp, bx

    mov bx, 3
    call getrandom
    mov di, ax
    mov [bp + 8], di
    mov [spawn_lane], di

    cmp di, 0
    je sbc_lane1
    cmp di, 1
    je sbc_lane2
    mov ax, [lanec3]
    jmp sbc_lane_ok

sbc_lane2:
    mov ax, [lanec2]
    jmp sbc_lane_ok

sbc_lane1:
    mov ax, [lanec1]

sbc_lane_ok:
    sub ax, CARHALFW
    mov cx, ax

    cmp cx, [colstart]
    jae sbc_chk_right
    mov cx, [colstart]
    jmp sbc_x_ok

sbc_chk_right:
    cmp cx, [colend]
    jbe sbc_x_ok
    mov cx, [colend]

sbc_x_ok:

    xor di, di
sbc_overlap_loop:
    cmp di, MAX_BLUE_CARS
    je sbc_no_overlap

    mov si, di
    call get_blue_car_ptr

    cmp word [bx], 1
    jne sbc_next

    mov al, [bx + 8]
    cmp al, [spawn_lane]
    jne sbc_next

    mov ax, [bx + 4]

    cmp ax, -CARH
    jl sbc_next

    cmp ax, CARH + 20
    jg sbc_next

    jmp near sbc_abort_spawn

sbc_next:
    inc di
    jmp sbc_overlap_loop

sbc_no_overlap:
    mov bx, bp

    mov word [bx], 1
    mov [bx + 2], cx
    mov ax, -CARH
    mov [bx + 4], ax
    add ax, CARH
    mov [bx + 6], ax

    jmp near sbc_done

sbc_abort_spawn:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

sbc_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; erase a coin sprite region around center CX,DX
erase_coin_at:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    sub cx, COIN_HALFW
    sub dx, COIN_HALFH
    mov [coin_base_x], cx
    mov [coin_base_y], dx

    xor si, si

erase_coin_row_loop:
    mov ax, [coin_base_y]
    add ax, si
    mov bp, ax

    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    mov ax, [coin_base_x]
    add di, ax

    mov bx, [coin_base_x]
    mov cx, COINW

erase_coin_col_loop:
    ; check overlap with red car
    mov ax, [redx]
    cmp bx, ax
    jb erase_not_red
    mov dx, ax
    add dx, CARW
    cmp bx, dx
    jae erase_not_red

    mov ax, bp
    cmp ax, [redy]
    jb erase_not_red
    mov dx, [redy]
    add dx, CARH
    cmp ax, dx
    jae erase_not_red

    mov ax, bp
    sub ax, [redy]
    mov dx, CARW
    mul dx
    mov dx, bx
    sub dx, [redx]
    add ax, dx
    push si
    mov si, car_sprite
    add si, ax
    mov al, [si]
    pop si
    or  al, al
    jz erase_not_red
    jmp erase_write_pixel

erase_not_red:
    cmp bx, ROADL
    jb erase_grass
    cmp bx, ROADR
    ja erase_grass

    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb erase_border

    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb erase_border

    cmp bx, [lane1]
    je erase_lane
    cmp bx, [lane2]
    je erase_lane

    mov al, COL_ASPHALT
    jmp erase_write_pixel

erase_border:
    mov al, COL_BORDER
    jmp erase_write_pixel

erase_lane:
    test bp, 3
    jnz erase_lane_asphalt
    mov al, COL_LANEYELLOW
    jmp erase_write_pixel

erase_lane_asphalt:
    mov al, COL_ASPHALT
    jmp erase_write_pixel

erase_grass:
    mov al, 0

erase_write_pixel:
    mov [es:di], al
    inc di
    inc bx
    dec cx
    jnz erase_coin_col_loop

    inc si
    cmp si, COINH
    jb erase_coin_row_loop
    
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; coins: erase, move, collision, respawn, draw
update_coins:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    cmp word [coin_spawn_timer], 0
    jle coin_do_spawn
    dec word [coin_spawn_timer]
    jmp coin_after_spawn


coin_do_spawn:
    call spawn_coin_once
    mov word [coin_spawn_timer], COIN_RESPAWN_DELAY

coin_after_spawn:
    xor si, si

coin_loop:
    mov bx, si
    shl bx, 1

    mov ax, [coin_active + bx]
    cmp ax, 0
    je coin_next

    mov ax, [coin_x + bx]
    mov cx, ax
    mov ax, [coin_y + bx]
    mov dx, ax
    call erase_coin_at

    mov ax, [coin_y + bx]
    add ax, COIN_SCROLL
    mov [coin_y + bx], ax

    cmp ax, SCR_HEIGHT
    jae coin_deactivate

    mov ax, [coin_x + bx]
    mov cx, ax
    mov dx, [coin_y + bx]
    call check_coin_collision
    cmp al, 1
    jne coin_no_hit

    mov ax, [coin_x + bx]
    mov cx, ax
    mov dx, [coin_y + bx]
    call erase_coin_at

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    inc word [coin_count]
    call draw_coin_hud
    jmp coin_deactivate

coin_no_hit:
    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle
    jmp coin_after_coin

coin_deactivate:
    mov word [coin_active + bx], 0

coin_after_coin:
coin_next:
    inc si
    cmp si, 3
    jb coin_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; draw fuel tank sprite (17x20) centered at AX,DX
; fueltank data uses -1 as transparent
draw_fuel_tank:
    ; AX = center X, DX = center Y
    sub ax, FUEL_HALFW
    sub dx, FUEL_HALFH
    mov [fuel_base_x], ax
    mov [fuel_base_y], dx

    pusha

    mov si, fueltank
    xor bx, bx          ; row counter

fuel_draw_row:
    cmp bx, FUELH
    jge fuel_draw_done

    mov ax, [fuel_base_y]
    add ax, bx
    cmp ax, 0
    jl fuel_skip_row
    cmp ax, SCR_HEIGHT
    jge fuel_draw_done

    mov cx, SCR_WIDTH
    mul cx
    mov di, ax
    mov ax, [fuel_base_x]
    add di, ax

    mov cx, FUELW

fuel_draw_col:
    lodsb
    cmp al, -1          ; -1 = transparent
    je fuel_skip_px
    mov [es:di], al
fuel_skip_px:
    inc di
    loop fuel_draw_col

fuel_skip_row:
    inc bx
    jmp fuel_draw_row

fuel_draw_done:
    popa
    ret

; check if fuel at CX,DX collides with red car
; returns AL = 1 if hit, 0 otherwise
check_fuel_collision:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    mov si, [redx]
    mov di, si
    add di, CARW
    
    mov bp, [redy]
    mov bx, bp
    add bx, CARH
    
    push cx
    push dx
    
    sub cx, FUEL_COLL_HALF
    mov ax, cx
    add ax, FUEL_COLL_SIZE
    
    sub dx, FUEL_COLL_HALF
    push dx
    add dx, FUEL_COLL_SIZE
    
    cmp ax, si
    jl fuel_no_collision_clean
    
    cmp cx, di
    jg fuel_no_collision_clean
    
    cmp dx, bp
    jl fuel_no_collision_clean
    
    pop ax
    cmp ax, bx
    jg fuel_no_collision_pop
    
    pop dx
    pop cx
    mov al, 1
    jmp fuel_collision_done
    
fuel_no_collision_clean:
    pop ax
fuel_no_collision_pop:
    pop dx
    pop cx
    mov al, 0
    
fuel_collision_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret

; erase a fuel tank area around center CX,DX
erase_fuel_at:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; convert center to top-left
    sub cx, FUEL_HALFW
    sub dx, FUEL_HALFH
    mov [fuel_base_x], cx
    mov [fuel_base_y], dx

    xor si, si              ; row index 0..FUELH-1

ef_row_loop:
    mov ax, [fuel_base_y]
    add ax, si              ; current y
    mov bp, ax              ; bp = y

    mov bx, SCR_WIDTH
    mul bx                  ; ax = y * 320
    mov di, ax
    mov ax, [fuel_base_x]
    add di, ax              ; di = video offset

    mov bx, [fuel_base_x]   ; bx = x for this row
    mov cx, FUELW           ; cx = number of columns

ef_col_loop:
    ; check overlap with red car bounding box
    mov ax, [redx]
    cmp bx, ax
    jb ef_not_red
    mov dx, ax
    add dx, CARW
    cmp bx, dx
    jae ef_not_red

    mov ax, bp
    cmp ax, [redy]
    jb ef_not_red
    mov dx, [redy]
    add dx, CARH
    cmp ax, dx
    jae ef_not_red

    ; inside red car → restore car pixel if non-transparent
    mov ax, bp
    sub ax, [redy]
    mov dx, CARW
    mul dx
    mov dx, bx
    sub dx, [redx]
    add ax, dx
    push si
    mov si, car_sprite
    add si, ax
    mov al, [si]
    pop si
    or  al, al
    jz ef_not_red
    jmp ef_write_pixel

ef_not_red:
    ; background (road / lane / border / grass)
    cmp bx, ROADL
    jb ef_grass
    cmp bx, ROADR
    ja ef_grass

    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb ef_border

    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb ef_border

    cmp bx, [lane1]
    je ef_lane
    cmp bx, [lane2]
    je ef_lane

    mov al, COL_ASPHALT
    jmp ef_write_pixel

ef_border:
    mov al, COL_BORDER
    jmp ef_write_pixel

ef_lane:
    test bp, 3
    jnz ef_lane_asphalt
    mov al, COL_LANEYELLOW
    jmp ef_write_pixel

ef_lane_asphalt:
    mov al, COL_ASPHALT
    jmp ef_write_pixel

ef_grass:
    mov al, 0

ef_write_pixel:
    mov [es:di], al
    inc di
    inc bx
    dec cx
    jnz ef_col_loop

    inc si
    cmp si, FUELH
    jb ef_row_loop

    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; fuel: erase, move, collision, respawn, draw
update_fuel:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    ; spawn timer
    cmp word [fuel_spawn_timer], 0
    jle fuel_do_spawn
    dec word [fuel_spawn_timer]
    jmp fuel_after_spawn

fuel_do_spawn:
    call spawn_fuel_once
    mov ax, [fuel_value]
    cmp ax, FUEL_LOW_THRESHOLD
    jle fuel_set_low_delay
    mov word [fuel_spawn_timer], FUEL_RESPAWN_DELAY
    jmp fuel_after_spawn

fuel_set_low_delay:
    mov word [fuel_spawn_timer], FUEL_RESPAWN_LOW

fuel_after_spawn:
    xor si, si

fuel_loop:
    mov bx, si
    shl bx, 1

    mov ax, [fuel_active + bx]
    cmp ax, 0
    je fuel_next

    ; erase old
    mov ax, [fuel_x + bx]
    mov cx, ax
    mov ax, [fuel_y + bx]
    mov dx, ax
    call erase_fuel_at

    ; move down
    mov ax, [fuel_y + bx]
    add ax, FUEL_SCROLL
    mov [fuel_y + bx], ax

    cmp ax, SCR_HEIGHT
    jae fuel_deactivate

    ; check collision with red car
    mov ax, [fuel_x + bx]
    mov cx, ax
    mov dx, [fuel_y + bx]
    call check_fuel_collision
    cmp al, 1
    jne fuel_no_hit

    ; hit: erase, redraw car, add fuel
    mov ax, [fuel_x + bx]
    mov cx, ax
    mov dx, [fuel_y + bx]
    call erase_fuel_at

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    ; add fuel (clamped to FUEL_MAX)
    mov ax, [fuel_value]
    add ax, FUEL_GAIN
    cmp ax, FUEL_MAX
    jle uf_store
    mov ax, FUEL_MAX
uf_store:
    mov [fuel_value], ax
    call draw_fuel_text
    call draw_fuel_hud


    jmp fuel_deactivate

fuel_no_hit:
    mov ax, [fuel_x + bx]
    mov dx, [fuel_y + bx]
    call draw_fuel_tank
    jmp fuel_after_entry

fuel_deactivate:
    mov word [fuel_active + bx], 0

fuel_after_entry:
fuel_next:
    inc si
    cmp si, 3
    jb fuel_loop

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; choose a random inactive lane and spawn one fuel tank
spawn_fuel_once:
    push ax
    push bx
    push cx
    push dx
    push si

    ; ----- 1. Find an inactive slot -----
    mov si, 0
    mov cx, 3

sfu_check_inactive:
    mov bx, si
    shl bx, 1
    mov ax, [fuel_active + bx]
    cmp ax, 0
    je sfu_use_slot          ; found free slot
    inc si
    loop sfu_check_inactive

    ; ----- 2. No inactive slot -> force replace lane 0 -----
    mov si, 0
    mov bx, 0

sfu_use_slot:
    mov [spawn_lane], si
    call spawn_fuel_lane

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; spawn fuel in lane SI, try to avoid overlap with blue cars
spawn_fuel_lane:
    push ax
    push bx
    push cx
    push dx
    push di

    mov dl, byte [spawn_lane]      ; lane index in DL

    mov bx, si
    shl bx, 1

    cmp si, 0
    je sfl_lane0
    cmp si, 1
    je sfl_lane1
    mov ax, [lanec3]
    jmp sfl_store_x

sfl_lane1:
    mov ax, [lanec2]
    jmp sfl_store_x

sfl_lane0:
    mov ax, [lanec1]

sfl_store_x:
    mov [fuel_x + bx], ax

    ; try to position relative to any blue car in this lane
    xor di, di
sfl_check_blue:
    push bx
    mov si, di
    call get_blue_car_ptr

    mov ax, [bx]
    cmp ax, 0
    je sfl_next_blue

    mov al, [bx + 8]       ; car's lane index
    cmp al, dl
    jne sfl_next_blue

    mov ax, [bx + 6]       ; car bottom y
    add ax, 32             ; place fuel some distance below

    cmp ax, SCR_HEIGHT - 40
    jbe sfl_candidate

    push bx
    mov bx, 50
    call getrandom
    add ax, FUEL_HALFH
    pop bx
    jmp sfl_store_y

sfl_candidate:
    cmp ax, SCR_HEIGHT - FUEL_HALFH
    jbe sfl_store_y
    mov ax, SCR_HEIGHT - FUEL_HALFH

sfl_store_y:
    pop bx
    mov [fuel_y + bx], ax
    jmp sfl_activate

sfl_next_blue:
    pop bx
    inc di
    cmp di, MAX_BLUE_CARS
    jb sfl_check_blue

    ; no matching blue car, pick a random height near top
    push bx
    mov bx, 50
    call getrandom
    add ax, FUEL_HALFH
    pop bx
    mov [fuel_y + bx], ax

sfl_activate:
    mov word [fuel_active + bx], 1

    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; choose a random inactive lane and spawn one coin
spawn_coin_once:
    push ax
    push bx
    push cx
    push dx
    push si

    ; ----- 1. find an inactive coin slot -----
    mov si, 0
    mov cx, 3

sco_check_slot:
    mov bx, si
    shl bx, 1
    mov ax, [coin_active + bx]
    cmp ax, 0
    je sco_use_slot
    inc si
    loop sco_check_slot

    ; no free slot → force use slot 0
    mov si, 0
    mov bx, 0

sco_use_slot:
    ; choose random lane 0..2
    mov bx, 3
    call getrandom
    mov [spawn_lane], ax   ; store lane index

    call spawn_coin_lane   ; do actual spawn

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; choose a random inactive lane and spawn one coin
; spawn coin in lane SI, avoid overlap with blue cars safely
spawn_coin_lane:
    push ax
    push bx
    push cx
    push dx
    push di
    push bp

    mov dl, [spawn_lane]      ; lane index 0..2

    ; bp = offset into coin arrays (si * 2)
    mov bx, si
    shl bx, 1
    mov bp, bx

    ; pick X center based on lane
    cmp si, 0
    je scl_lane0
    cmp si, 1
    je scl_lane1
    mov ax, [lanec3]
    jmp scl_store_x

scl_lane1:
    mov ax, [lanec2]
    jmp scl_store_x

scl_lane0:
    mov ax, [lanec1]

scl_store_x:
    mov [coin_x + bp], ax

    ; try to place above a blue car in same lane
    xor di, di

scl_check_blue:
    cmp di, MAX_BLUE_CARS
    jae scl_no_blue_same_lane

    mov si, di
    call get_blue_car_ptr     ; BX = pointer to this blue car

    mov ax, [bx]              ; active?
    cmp ax, 0
    je scl_next_blue

    mov al, [bx + 8]          ; car lane index
    cmp al, dl
    jne scl_next_blue

    ; place coin above this blue car
    mov ax, [bx + 4]          ; car top Y
    sub ax, COINH             ; coin goes above it
    cmp ax, 20
    jge scl_y_ok
    mov ax, 20
scl_y_ok:
    mov [coin_y + bp], ax
    jmp scl_activate

scl_next_blue:
    inc di
    jmp scl_check_blue


; no matching blue car → random height
scl_no_blue_same_lane:
    mov bx, 50
    call getrandom            ; ax = 0..49
    add ax, COIN_HALFH
    mov [coin_y + bp], ax

scl_activate:
    mov word [coin_active + bp], 1

    pop bp
    pop di
    pop dx
    pop cx
    pop bx
    pop ax
    ret

; check if coin at CX,DX collides with red car
check_coin_collision:
    push bx
    push cx
    push dx
    push si
    push di
    push bp
    
    mov si, [redx]
    mov di, si
    add di, CARW
    
    mov bp, [redy]
    mov bx, bp
    add bx, CARH
    
    push cx
    push dx
    
    sub cx, COIN_COLL_HALF
    mov ax, cx
    add ax, COIN_COLL_SIZE
    
    sub dx, COIN_COLL_HALF
    push dx
    add dx, COIN_COLL_SIZE
    
    cmp ax, si
    jl coin_no_collision_clean
    
    cmp cx, di
    jg coin_no_collision_clean
    
    cmp dx, bp
    jl coin_no_collision_clean
    
    pop ax
    cmp ax, bx
    jg coin_no_collision_pop
    
    pop dx
    pop cx
    mov al, 1
    jmp coin_collision_done
    
coin_no_collision_clean:
    pop ax
coin_no_collision_pop:
    pop dx
    pop cx
    mov al, 0
    
coin_collision_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    ret


; erase any car (red or blue) at CX,DX using road background
erase_car:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov ax, dx
    cmp ax, SCR_HEIGHT
    jl erase_car_check_top
    jmp erase_car_done

erase_car_check_top:
    mov ax, dx
    add ax, CARH
    cmp ax, 0
    jg erase_car_compute
    jmp erase_car_done

erase_car_compute:
    mov bp, dx
    cmp bp, 0
    jge erase_car_y_start_ok
    xor bp, bp
erase_car_y_start_ok:
    mov ax, dx
    add ax, CARH
    cmp ax, SCR_HEIGHT
    jle erase_car_y_end_ok
    mov ax, SCR_HEIGHT
erase_car_y_end_ok:
    sub ax, bp
    mov si, ax

    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx

erase_car_row_loop:
    cmp si, 0
    jle erase_car_done

    push cx
    push dx
    push si

    mov cx, CARW

erase_car_col_loop:
    push di
    push cx

    mov ax, di
    xor dx, dx
    mov bx, SCR_WIDTH
    div bx
    mov bx, dx

    cmp bx, ROADL
    jb erase_car_grass
    cmp bx, ROADR
    ja erase_car_grass

    mov ax, bx
    sub ax, ROADL
    cmp ax, BORDERW
    jb erase_car_border

    mov ax, ROADR
    sub ax, bx
    cmp ax, BORDERW
    jb erase_car_border

    cmp bx, [lane1]
    je erase_car_lane
    cmp bx, [lane2]
    je erase_car_lane

    mov al, COL_ASPHALT
    jmp erase_car_write

erase_car_border:
    mov al, COL_BORDER
    jmp erase_car_write

erase_car_lane:
    test bp, 3
    jnz erase_car_lane_asphalt
    mov al, COL_LANEYELLOW
    jmp erase_car_write

erase_car_lane_asphalt:
    mov al, COL_ASPHALT
    jmp erase_car_write

erase_car_grass:
    mov al, 0

erase_car_write:
    pop cx
    pop di
    mov [es:di], al
    inc di
    loop erase_car_col_loop

    pop si
    pop dx
    pop cx

    inc bp
    dec si
    jz erase_car_done

    mov ax, SCR_WIDTH
    sub ax, CARW
    add di, ax
    jmp erase_car_row_loop

erase_car_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; move red car left between lanes
move_red_left:
    push ax

    mov al, [red_lane]
    cmp al, 0
    jbe move_red_left_no_dec
    dec al
    mov [red_lane], al
move_red_left_no_dec:
    xor ah, ah

    cmp ax, 0
    je move_red_left_lane1
    cmp ax, 1
    je move_red_left_lane2
    mov ax, [lanec3]
    jmp move_red_left_store

move_red_left_lane2:
    mov ax, [lanec2]
    jmp move_red_left_store

move_red_left_lane1:
    mov ax, [lanec1]

move_red_left_store:
    sub ax, CARHALFW
    mov [redx], ax

    pop ax
    ret


; move red car right between lanes
move_red_right:
    push ax

    mov al, [red_lane]
    cmp al, 2
    jae move_red_right_no_inc
    inc al
    mov [red_lane], al
move_red_right_no_inc:
    xor ah, ah

    cmp ax, 0
    je move_red_right_lane1
    cmp ax, 1
    je move_red_right_lane2
    mov ax, [lanec3]
    jmp move_red_right_store

move_red_right_lane2:
    mov ax, [lanec2]
    jmp move_red_right_store

move_red_right_lane1:
    mov ax, [lanec1]

move_red_right_store:
    sub ax, CARHALFW
    mov [redx], ax

    pop ax
    ret

; draw simple spark burst around the red car center
draw_spark:
    pusha

    ; make sure ES points to VGA memory
    mov ax, VIDSEG
    mov es, ax

    ; center of red car
    mov ax, [redx]
    add ax, CARHALFW
    mov si, ax              ; center x

    mov ax, CARH
    shr ax, 1
    add ax, [redy]
    mov di, ax              ; center y

    mov cx, 25              ; number of spark pixels

spark_loop:
    ; random x offset in range -8..+7
    mov bx, 16
    call getrandom          ; ax = 0..15
    sub ax, 8
    add ax, si              ; ax = x

    ; clamp x to 0..SCR_WIDTH-1
    cmp ax, 0
    jl spark_next
    cmp ax, SCR_WIDTH-1
    jg spark_next
    mov dx, ax              ; dx = x

    ; random y offset in range -8..+7
    mov bx, 16
    call getrandom          ; ax = 0..15
    sub ax, 8
    add ax, di              ; ax = y

    ; clamp y to 0..SCR_HEIGHT-1
    cmp ax, 0
    jl spark_next
    cmp ax, SCR_HEIGHT-1
    jg spark_next

    ; compute video offset: y*320 + x
    mov bx, SCR_WIDTH
    mul bx                  ; ax = y*320
    add ax, dx              ; + x
    mov di, ax

    ; draw bright yellow pixel (14)
    mov byte [es:di], 14

spark_next:
    loop spark_loop

    popa
    ret

; check if changing into a side lane would crash into a blue car
; IN:  AL = target lane index (0,1,2)
; OUT: AL = 1 if crash, 0 if safe
check_side_lane_collision:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    ; default: no crash
    mov byte [tmp_side_flag], 0
    mov [tmp_target_lane], al

    ; red car vertical range
    mov ax, [redy]
    mov [tmp_side_top], ax
    add ax, CARH
    mov [tmp_side_bottom], ax

    xor si, si

csl_loop:
    call get_blue_car_ptr

    ; active?
    mov ax, [bx]
    cmp ax, 0
    je csl_next

    ; y valid?
    mov ax, [bx + 4]
    cmp ax, 0FFFFh
    je csl_next
    cmp ax, SCR_HEIGHT
    jge csl_next

    ; same lane?
    mov dl, [bx + 8]
    mov al, [tmp_target_lane]
    cmp dl, al
    jne csl_next

    ; blue vertical range
    mov dx, [bx + 4]    ; blue top
    mov bp, dx
    add bp, CARH        ; blue bottom

    ; check vertical overlap:
    ; red_bottom > blue_top AND red_top < blue_bottom
    mov ax, [tmp_side_bottom]
    cmp ax, dx
    jle csl_next

    mov ax, [tmp_side_top]
    cmp bp, ax
    jle csl_next

    ; overlap in target lane -> crash
    mov byte [tmp_side_flag], 1
    jmp csl_done

csl_next:
    inc si
    cmp si, MAX_BLUE_CARS
    jb csl_loop

csl_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax

    mov al, [tmp_side_flag]
    ret

; check collision between red car and all blue cars
check_blue_collisions:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov word [game_over_flag], 0

    mov ax, [redx]
    add ax, CARHALFW
    mov bx, ax

    mov ax, bx
    sub ax, [lanec1]
    jns cbc_abs1
    neg ax
cbc_abs1:
    mov dx, ax
    mov byte [red_lane], 0

    mov ax, bx
    sub ax, [lanec2]
    jns cbc_abs2
    neg ax
cbc_abs2:
    cmp ax, dx
    jge cbc_check3
    mov dx, ax
    mov byte [red_lane], 1

cbc_check3:
    mov ax, bx
    sub ax, [lanec3]
    jns cbc_abs3
    neg ax
cbc_abs3:
    cmp ax, dx
    jge cbc_lane_done
    mov byte [red_lane], 2

cbc_lane_done:

    mov ax, [redx]
    mov [red_left], ax
    add ax, CARW
    mov [red_right], ax
    mov ax, [redy]
    mov [red_top], ax
    add ax, CARH
    mov [red_bottom], ax

    mov al, [red_lane]

    xor si, si
cbc_loop:
    call get_blue_car_ptr

    mov dx, [bx]
    cmp dx, 0
    je cbc_next

    mov dx, [bx + 4]
    cmp dx, 0FFFFh
    je cbc_next
    cmp dx, SCR_HEIGHT
    jge cbc_next

    cmp al, [bx + 8]
    jne cbc_next

    mov cx, [bx + 2]
    mov di, cx
    add di, CARW
    mov dx, [bx + 4]
    push ax
    mov ax, dx
    add ax, CARH
    mov bp, ax
    pop ax

    mov dx, [red_right]
    cmp dx, cx
    jle cbc_next

    mov dx, [red_left]
    cmp di, dx
    jle cbc_next

    mov dx, [red_bottom]
    push ax
    mov ax, [bx + 4]
    cmp dx, ax
    pop ax
    jle cbc_next

    mov dx, [red_top]
    cmp bp, dx
    jle cbc_next

    ; collision detected – show sparks
    call draw_spark

; small pause so spark becomes visible
    mov cx, 30000        ; adjust if needed
spark_delay:
    loop spark_delay

    mov word [game_over_flag], 1
    mov byte [end_reason], REASON_CRASH
    jmp cbc_done

cbc_next:
    inc si
    cmp si, MAX_BLUE_CARS
    jb cbc_loop

cbc_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw road and background
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
    jb bg_outside_road
    cmp ax, ROADR
    ja bg_outside_road

    mov ax, si
    sub ax, ROADL
    cmp ax, BORDERW
    jb bg_border

    mov ax, ROADR
    sub ax, si
    cmp ax, BORDERW
    jb bg_border

    mov al, COL_ASPHALT

    mov dx, si
    cmp dx, [lane1]
    je bg_maybe_dash
    cmp dx, [lane2]
    je bg_maybe_dash
    jmp bg_write_pixel
        
bg_border:
    mov al, COL_BORDER
    jmp bg_write_pixel
        
bg_maybe_dash:
    test bp, 3
    jnz bg_write_pixel
    mov al, COL_LANEYELLOW
    jmp bg_write_pixel
        
bg_outside_road:
    mov al, 0
        
bg_write_pixel:
    mov [es:di], al
    inc di
    inc si
    loop bg_col_loop
    inc bp

    cmp di, SCR_WIDTH*SCR_HEIGHT
    jae bg_done
    jmp bg_row_loop

bg_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw red car at (CX,DX)
draw_car_red:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    mov ax, dx
    mov bx, SCR_WIDTH
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
    cmp al, -1
    jz draw_red_skip
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


; draw blue car with clipping at (CX,DX)
draw_car_blue:
    push ax
    push bx
    push cx
    push dx
    push si
    push di
    push bp

    mov bp, dx
    add bp, CARH
    
    mov si, 0
    cmp dx, 0
    jge blue_start_ok
    
    neg dx
    mov si, dx
    mov dx, 0
    
blue_start_ok:
    mov ax, bp
    sub ax, dx
    cmp ax, CARH
    jbe blue_height_ok
    mov ax, CARH
blue_height_ok:
    cmp ax, 0
    jle blue_draw_done
    
    cmp dx, SCR_HEIGHT
    jge blue_draw_done
    
    mov bx, dx
    add bx, ax
    cmp bx, SCR_HEIGHT
    jbe blue_no_bottom_clip
    mov ax, SCR_HEIGHT
    sub ax, dx
    
blue_no_bottom_clip:
    mov bp, ax
    
    mov ax, dx
    push dx
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, cx
    pop dx

    mov ax, si
    mov bx, CARW
    mul bx
    mov si, car_blue_sprite
    add si, ax

    mov cx, bp
    
draw_blue_row:
    push cx
    push di
    mov cx, CARW
    
draw_blue_col:
    lodsb
    cmp al, -1
    jz  draw_blue_skip
    cmp al, 12
    jne chk_blue_red
    mov al, 9
    jmp blue_store

chk_blue_red:
    cmp al, 4
    jne chk_blue_dark
    mov al, 1
    jmp blue_store

chk_blue_dark:
    cmp al, 3
    jne blue_store
    mov al, 1
    
blue_store:
    mov [es:di], al
    
draw_blue_skip:
    inc di
    loop draw_blue_col
    pop di
    add di, SCR_WIDTH
    pop cx
    loop draw_blue_row

blue_draw_done:
    pop bp
    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; draw coin sprite (20x30) centered at AX,DX
draw_coin_circle:
    sub ax, COIN_HALFW
    sub dx, COIN_HALFH
    mov [coin_base_x], ax
    mov [coin_base_y], dx

    pusha

    mov si, coin
    xor bx, bx

draw_coin_row:
    cmp bx, COINH
    jge draw_coin_done

    mov ax, [coin_base_y]
    add ax, bx
    cmp ax, 0
    jl skip_row
    cmp ax, SCR_HEIGHT
    jge draw_coin_done

    mov cx, SCR_WIDTH
    mul cx
    mov di, ax
    mov ax, [coin_base_x]
    add di, ax

    mov cx, COINW

draw_coin_col:
    lodsb
    cmp al, 0
    je skip_px
    mov [es:di], al
skip_px:
    inc di
    loop draw_coin_col

skip_row:
    inc bx
    jmp draw_coin_row

draw_coin_done:
    popa
    ret


; draw fuel HUD bar (bottom bar, color depends on fuel)
draw_fuel_hud: 
    pusha

    ; bottom "FUEL" label (same as before)
    mov ah, 02h
    xor bh, bh
    mov dh, 22
    mov dl, 2
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Ah

    mov al, 'F'
    int 10h
    mov al, 'U'
    int 10h
    mov al, 'E'
    int 10h
    mov al, 'L'
    int 10h

    ; draw bar based on fuel_value
    mov ax, VIDSEG
    mov es, ax

    ; start at y=184, x=8
    mov bp, 184
    mov ax, bp
    mov bx, SCR_WIDTH
    mul bx
    mov di, ax
    add di, 8

    ; clamp fuel_value to 0..FUEL_MAX
    mov ax, [fuel_value]
    cmp ax, 0
    jge dfh_not_neg
    xor ax, ax
dfh_not_neg:
    cmp ax, FUEL_MAX
    jle dfh_ok_max
    mov ax, FUEL_MAX
dfh_ok_max:
    mov dx, ax          ; dx = segments filled (0..12)

        ; choose color:
    ; <4  = red (4)
    ; <8  = yellow (14)
    ; else = green (2)

    cmp dx, 4
    jl dfh_red          ; fuel < 4 → red

    cmp dx, 8
    jl dfh_yellow       ; fuel < 8 → yellow

    mov bl, 2           ; green
    jmp dfh_color_done

dfh_red:
    mov bl, 4
    jmp dfh_color_done

dfh_yellow:
    mov bl, 14

dfh_color_done:
    ; draw 12 segments, each 2x8 pixels, with 2px gap (add di,4)
    xor si, si          ; si = segment index 0..11
    mov cx, 12

dfh_seg_loop:
    push cx
    push di

    mov bh, 8           ; 8 rows high
dfh_row_loop:
    push di
    mov cx, 2           ; 2 columns wide
dfh_col_loop:
    mov al, 0           ; empty by default
    cmp si, dx
    jae dfh_empty_px    ; if segment index >= filled count => empty
    mov al, bl          ; filled => chosen color
dfh_empty_px:
    mov [es:di], al
    inc di
    loop dfh_col_loop
    pop di
    add di, SCR_WIDTH
    dec bh
    jnz dfh_row_loop

    pop di
    pop cx
    add di, 4           ; move to next segment slot
    inc si
    loop dfh_seg_loop

    popa
    ret

; draw coin HUD
; draw coin HUD
draw_coin_hud:
    pusha

    ; move to top-left
    mov ah, 02h
    xor bh, bh
    mov dh, 0
    mov dl, 0
    int 10h

    ; print "COINS: "
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_coins
coin_label_loop:
    lodsb
    or al, al
    jz coin_label_done
    int 10h
    jmp coin_label_loop
coin_label_done:

    ; clear old digits area (5 spaces)
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh

    mov cx, 5
clear_coin_digits:
    mov al, ' '
    int 10h
    loop clear_coin_digits

        ; move cursor to after label ("COINS: " = 7 chars)
    mov ah, 02h
    xor bh, bh
    mov dh, 0
    mov dl, 7
    int 10h

    ; clamp coin_count to 0..999 and print as 3 digits (000–999)
    mov ax, [coin_count]
    cmp ax, 0
    jge dch_not_neg
    xor ax, ax
dch_not_neg:
    cmp ax, 999
    jle dch_ok_max
    mov ax, 999
dch_ok_max:
    call print_dec3
    popa
    ret

; draw fuel HUD text
draw_fuel_text:
    pusha

    ; move to row 1, col 0
    mov ah, 02h
    xor bh, bh
    mov dh, 1
    mov dl, 0
    int 10h

    ; print "FUEL: "
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov si, msg_fuel
fuel_label_loop:
    lodsb
    or al, al
    jz fuel_label_done
    int 10h
    jmp fuel_label_loop
fuel_label_done:

    ; clear old digits area (5 spaces)
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh

    mov cx, 5
clear_fuel_digits:
    mov al, ' '
    int 10h
    loop clear_fuel_digits


        ; move cursor to after "FUEL: " (6 chars)
    mov ah, 02h
    xor bh, bh
    mov dh, 1
    mov dl, 6
    int 10h

    ; clamp fuel_value to 0..99 and print as 2 digits (00–99)
    mov ax, [fuel_value]
    cmp ax, 0
    jge dft_not_neg
    xor ax, ax
dft_not_neg:
    cmp ax, 99
    jle dft_ok_max
    mov ax, 99
dft_ok_max:
    call print_dec2
    popa
    ret

; print decimal number in AX
print_dec:
    push ax
    push bx
    push cx
    push dx
    push si

    mov si, digit_buf + 4
    mov bx, 10
    xor cx, cx

    cmp ax, 0
    jne print_dec_convert
    mov byte [si], '0'
    mov cx, 1
    jmp print_dec_print
; print AX as 3 digits (000–999)
print_dec3:
    push ax
    push bx
    push cx
    push dx

    ; AX = value
    mov bx, 100
    xor dx, dx
    div bx              ; DX:AX / 100 → AX = hundreds, DX = remainder
    mov cx, ax          ; CX = hundreds (0..9)

    ; print hundreds
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, cl
    add al, '0'
    int 10h

    ; AX = remainder (0..99)
    mov ax, dx
    mov bx, 10
    xor dx, dx
    div bx              ; AX = tens (0..9), DX = ones (0..9)

    ; print tens
    mov al, al          ; AX already has tens in low byte
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    int 10h

    ; print ones
    mov al, dl
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret


; print AX as 2 digits (00–99)
print_dec2:
    push ax
    push bx
    push cx
    push dx

    ; AX = value (0..99)
    mov bx, 10
    xor dx, dx
    div bx              ; AX = tens (0..9), DX = ones (0..9)

    ; print tens
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, al
    add al, '0'
    int 10h

    ; print ones
    mov al, dl
    add al, '0'
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    int 10h

    pop dx
    pop cx
    pop bx
    pop ax
    ret

print_dec_convert:
print_dec_div_loop:
    xor dx, dx
    div bx
    add dl, '0'
    mov [si], dl
    dec si
    inc cx
    cmp ax, 0
    jne print_dec_div_loop

print_dec_print:
    inc si

print_dec_print_loop:
    mov al, [si]
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    int 10h
    inc si
    loop print_dec_print_loop

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; start menu
show_start_screen:
    pusha

    mov ax, VIDSEG
    mov es, ax
    xor di, di
    mov al, 0
    mov cx, SCR_WIDTH*SCR_HEIGHT
    rep stosb

    ; title
    mov ah, 02h
    xor bh, bh
    mov dh, 8
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bl, 0Eh
    mov si, msg_title

menu_t:
    lodsb
    or al, al
    jz menu_t_done
    int 10h
    jmp menu_t
menu_t_done:

    ; play option
    mov ah, 02h
    mov dh, 12
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_menu_play

menu_p:
    lodsb
    or al, al
    jz menu_p_done
    int 10h
    jmp menu_p
menu_p_done:

    ; exit option
    mov ah, 02h
    mov dh, 14
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_menu_exit

menu_e:
    lodsb
    or al, al
    jz menu_e_done
    int 10h
    jmp menu_e
menu_e_done:

    ; credits
    mov ah, 02h
    mov dh, 22
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov si, msg_credit1

credit1:
    lodsb
    or al, al
    jz credit1_done
    int 10h
    jmp credit1
credit1_done:

    mov ah, 02h
    mov dh, 23
    mov dl, 8
    int 10h

    mov ah, 0Eh
    mov si, msg_credit2

credit2:
    lodsb
    or al, al
    jz credit2_done
    int 10h
    jmp credit2
credit2_done:

menu_wait_choice:
    mov ah, 0
    int 16h
    cmp al, 'p'
    je menu_play_choice
    cmp al, 'P'
    je menu_play_choice
    cmp al, 'e'
    je menu_exit_choice
    cmp al, 'E'
    je menu_exit_choice
    jmp menu_wait_choice

menu_play_choice:
    popa
    ret

menu_exit_choice:
    popa
    jmp near exit_to_dos


; player info screen: name + roll input
show_player_info_screen:
    pusha

    mov ax, VIDSEG
    mov es, ax
    xor di, di
    mov al, 0
    mov cx, SCR_WIDTH*SCR_HEIGHT
    rep stosb

    mov byte [player_name_len], 0
    mov byte [player_roll_len], 0

    ; draw box
    mov ax, VIDSEG
    mov es, ax
    mov bx, 60
spis_row:
    mov ax, bx
    mov cx, SCR_WIDTH
    mul cx
    add ax, 40
    mov di, ax
    mov cx, 240
    mov al, 1
    rep stosb
    inc bx
    cmp bx, 140
    jbe spis_row

    ; title
    mov ah, 02h
    xor bh, bh
    mov dh, 8
    mov dl, 14
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_info_title
spis_title:
    lodsb
    or al, al
    jz spis_title_done
    int 10h
    jmp spis_title
spis_title_done:

    ; Name label (red)
    mov ah, 02h
    mov dh, 11
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Ch
    mov si, msg_name_label
spis_name_label:
    lodsb
    or al, al
    jz spis_name_label_done
    int 10h
    jmp spis_name_label
spis_name_label_done:

    ; Roll label (yellow)
    mov ah, 02h
    mov dh, 14
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Eh
    mov si, msg_roll_label
spis_roll_label:
    lodsb
    or al, al
    jz spis_roll_label_done
    int 10h
    jmp spis_roll_label
spis_roll_label_done:

    ; read name (max 20)
    mov ah, 02h
    mov dh, 11
    mov dl, 18
    int 10h

    call read_name_input

    ; read roll (max 10)
    mov ah, 02h
    mov dh, 14
    mov dl, 18
    int 10h

    call read_roll_input

    popa
    ret


; read name into player_name (20 chars), with slow blinking cursor
read_name_input:
    push ax
    push bx
    push cx
    push dx
    push si

    mov byte [player_name_len], 0

name_input_loop:
    ; blink cursor at next char position
    mov ah, 02h
    xor bh, bh
    mov dh, 11
    mov al, [player_name_len]
    mov dl, 18
    add dl, al
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, '_'
    int 10h

    mov cx, 40000
name_cursor_on_delay:
    loop name_cursor_on_delay

    mov ah, 01h
    int 16h
    jnz name_key_ready

    ; turn cursor off
    mov ah, 02h
    xor bh, bh
    mov dh, 11
    mov al, [player_name_len]
    mov dl, 18
    add dl, al
    int 10h

    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov cx, 40000
name_cursor_off_delay:
    loop name_cursor_off_delay

    mov ah, 01h
    int 16h
    jz name_input_loop

name_key_ready:
    ; erase cursor before reading
    mov ah, 02h
    xor bh, bh
    mov dh, 11
    mov al, [player_name_len]
    mov dl, 18
    add dl, al
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov ah, 0
    int 16h

    cmp al, 13
    je name_enter
    cmp al, 8
    je name_backspace

    cmp byte [player_name_len], 20
    jae name_input_loop

    ; store char
    mov bl, [player_name_len]
    mov bh, 0
    mov si, player_name
    add si, bx
    mov [si], al
    inc byte [player_name_len]

    ; echo char
    mov ah, 02h
    xor bh, bh
    mov dh, 11
    mov dl, 18
    add dl, bl
    int 10h
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, [si]
    int 10h

    jmp name_input_loop

name_backspace:
    cmp byte [player_name_len], 0
    jz name_input_loop
    dec byte [player_name_len]
    mov bl, [player_name_len]
    mov bh, 0
    mov si, player_name
    add si, bx
    mov byte [si], 0

    mov ah, 02h
    xor bh, bh
    mov dh, 11
    mov dl, 18
    add dl, bl
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h
    jmp name_input_loop

name_enter:
    cmp byte [player_name_len], 0
    jz name_input_loop

    ; zero-terminate
    mov bl, [player_name_len]
    mov bh, 0
    mov si, player_name
    add si, bx
    mov byte [si], 0

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; read roll into player_roll (10 chars), slow blinking cursor
read_roll_input:
    push ax
    push bx
    push cx
    push dx
    push si

    mov byte [player_roll_len], 0

roll_input_loop:
    ; blink cursor at next char position
    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov al, [player_roll_len]
    mov dl, 18
    add dl, al
    int 10h

    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, '_'
    int 10h

    mov cx, 40000
roll_cursor_on_delay:
    loop roll_cursor_on_delay

    mov ah, 01h
    int 16h
    jnz roll_key_ready

    ; turn cursor off
    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov al, [player_roll_len]
    mov dl, 18
    add dl, al
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov cx, 40000
roll_cursor_off_delay:
    loop roll_cursor_off_delay

    mov ah, 01h
    int 16h
    jz roll_input_loop

roll_key_ready:
    ; erase cursor before reading
    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov al, [player_roll_len]
    mov dl, 18
    add dl, al
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov ah, 0
    int 16h

    cmp al, 13
    je roll_enter
    cmp al, 8
    je roll_backspace

    cmp byte [player_roll_len], 10
    jae roll_input_loop

    mov bl, [player_roll_len]
    mov bh, 0
    mov si, player_roll
    add si, bx
    mov [si], al
    inc byte [player_roll_len]

    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov dl, 18
    add dl, bl
    int 10h
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh
    mov al, [si]
    int 10h

    jmp roll_input_loop

roll_backspace:
    cmp byte [player_roll_len], 0
    jz roll_input_loop
    dec byte [player_roll_len]
    mov bl, [player_roll_len]
    mov bh, 0
    mov si, player_roll
    add si, bx
    mov byte [si], 0

    mov ah, 02h
    xor bh, bh
    mov dh, 14
    mov dl, 18
    add dl, bl
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h
    jmp roll_input_loop

roll_enter:
    cmp byte [player_roll_len], 0
    jz roll_input_loop

    mov bl, [player_roll_len]
    mov bh, 0
    mov si, player_roll
    add si, bx
    mov byte [si], 0

    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; tutorial screen
; only arrows flicker (no brackets), only S flickers, slower
show_instruction_screen:
    pusha

    mov ax, VIDSEG
    mov es, ax
    xor di, di
    mov al, 0
    mov cx, SCR_WIDTH*SCR_HEIGHT
    rep stosb

    ; title
    mov ah, 02h
    xor bh, bh
    mov dh, 4
    mov dl, 10
    int 10h

    mov ah, 0Eh
    mov bl, 0Eh
    mov si, msg_instr_title
si_title:
    lodsb
    or al, al
    jz si_title_done
    int 10h
    jmp si_title
si_title_done:

    ; movement lines
    mov ah, 02h
    mov dh, 8
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_left_line
si_left:
    lodsb
    or al, al
    jz si_left_done
    int 10h
    jmp si_left
si_left_done:

    mov ah, 02h
    mov dh, 10
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov si, msg_right_line
si_right:
    lodsb
    or al, al
    jz si_right_done
    int 10h
    jmp si_right
si_right_done:

    mov ah, 02h
    mov dh, 12
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov si, msg_up_line
si_up:
    lodsb
    or al, al
    jz si_up_done
    int 10h
    jmp si_up
si_up_done:

    mov ah, 02h
    mov dh, 14
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov si, msg_down_line
si_down:
    lodsb
    or al, al
    jz si_down_done
    int 10h
    jmp si_down
si_down_done:

    ; coin line left aligned
    mov ah, 02h
    mov dh, 17
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov si, msg_collect_line
si_collect:
    lodsb
    or al, al
    jz si_collect_done
    int 10h
    jmp si_collect
si_collect_done:

    ; fuel line left aligned
    mov ah, 02h
    mov dh, 19
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov si, msg_fuel_line
si_fuel:
    lodsb
    or al, al
    jz si_fuel_done
    int 10h
    jmp si_fuel
si_fuel_done:

    ; draw brackets row once: [ ]  [ ]  [ ]  [ ]
    mov ah, 02h
    xor bh, bh
    mov dh, 21
    mov dl, 4
    int 10h
    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_arrow_brackets
si_brackets:
    lodsb
    or al, al
    jz si_brackets_done
    int 10h
    jmp si_brackets
si_brackets_done:

    ; base "Press   to start" on tutorial screen (S will blink only)
    mov ah, 02h
    mov dh, 23
    mov dl, 8
    int 10h
    mov ah, 0Eh
    mov si, msg_press_s_base
si_press_base:
    lodsb
    or al, al
    jz si_press_base_done
    int 10h
    jmp si_press_base
si_press_base_done:

si_blink_loop:
    ; show arrows characters only
    mov ah, 0Eh
    mov bh, 0
    mov bl, 0Fh

    ; '<' inside first [ ]
    mov ah, 02h
    mov dh, 21
    mov dl, 5
    int 10h
    mov ah, 0Eh
    mov al, '<'
    int 10h

    ; '^'
    mov ah, 02h
    mov dh, 21
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov al, '^'
    int 10h

    ; '>'
    mov ah, 02h
    mov dh, 21
    mov dl, 15
    int 10h
    mov ah, 0Eh
    mov al, '>'
    int 10h

    ; 'v'
    mov ah, 02h
    mov dh, 21
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov al, 'v'
    int 10h

    ; show S in "Press S to start" (base string already "Press   to start")
    mov ah, 02h
    mov dh, 23
    mov dl, 8
    add dl, 6        ; position of S
    int 10h
    mov ah, 0Eh
    mov al, 'S'
    int 10h

    mov cx, 65000            ; slower ON delay
si_delay_on:
    loop si_delay_on

    ; check key
    mov ah, 01h
    int 16h
    jnz si_key_check

    ; hide arrows
    mov ah, 02h
    mov dh, 21
    mov dl, 5
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov ah, 02h
    mov dh, 21
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov ah, 02h
    mov dh, 21
    mov dl, 15
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov ah, 02h
    mov dh, 21
    mov dl, 20
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    ; hide S
    mov ah, 02h
    mov dh, 23
    mov dl, 8
    add dl, 6
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov cx, 65000            ; slower OFF delay
si_delay_off:
    loop si_delay_off

    mov ah, 01h
    int 16h
    jz si_blink_loop

si_key_check:
    mov ah, 0
    int 16h
    cmp al, 's'
    je si_exit
    cmp al, 'S'
    je si_exit
    jmp si_blink_loop

si_exit:
    popa
    ret


; "Press S to start" overlay on static road screen (only S blinking, slower)
show_press_to_start_overlay:
    pusha

    ; base text "Press   to start"
overlay_base:
    mov ah, 02h
    xor bh, bh
    mov dh, 21
    mov dl, 22
    int 10h
    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_press_s_base
overlay_print_base:
    lodsb
    or al, al
    jz overlay_base_done
    int 10h
    jmp overlay_print_base
overlay_base_done:

overlay_loop:
    ; draw S at its spot
    mov ah, 02h
    xor bh, bh
    mov dh, 21
    mov dl, 22
    add dl, 6       ; inside "Press   to start"
    int 10h
    mov ah, 0Eh
    mov al, 'S'
    int 10h

    mov cx, 65000           ; slower ON delay
ov_delay_on:
    loop ov_delay_on

    mov ah, 01h
    int 16h
    jnz overlay_key_ready

    ; erase S
    mov ah, 02h
    xor bh, bh
    mov dh, 21
    mov dl, 22
    add dl, 6
    int 10h
    mov ah, 0Eh
    mov al, ' '
    int 10h

    mov cx, 65000           ; slower OFF delay
ov_delay_off:
    loop ov_delay_off

    mov ah, 01h
    int 16h
    jz overlay_loop

overlay_key_ready:
    mov ah, 0
    int 16h
    cmp al, 's'
    je start_overlay_accept
    cmp al, 'S'
    je start_overlay_accept
    jmp overlay_loop

start_overlay_accept:
    call redraw_full_scene
    popa
    ret


; confirm exit prompt (ESC)
confirm_exit:
    pusha

    mov ax, VIDSEG
    mov es, ax

    mov bx, 70
ce_row:
    mov ax, bx
    mov cx, SCR_WIDTH
    mul cx
    add ax, 80
    mov di, ax
    mov cx, 160
    mov al, 1
    rep stosb

    inc bx
    cmp bx, 130
    jbe ce_row

    mov ah, 02h
    xor bh, bh
    mov dh, 12
    mov dl, 11
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_confirm_exit

ce_print:
    lodsb
    or al, al
    jz ce_print_done
    int 10h
    jmp ce_print
ce_print_done:

ce_wait_key:
    mov ah, 0
    int 16h
    cmp al, 'y'
    je ce_yes
    cmp al, 'Y'
    je ce_yes
    cmp al, 'n'
    je ce_no
    cmp al, 'N'
    je ce_no
    jmp ce_wait_key

ce_yes:
    mov byte [confirm_choice], 1
    jmp ce_end

ce_no:
    mov byte [confirm_choice], 0

ce_end:
    popa
    mov al, [confirm_choice]
    ret


; redraw whole screen
redraw_full_scene:
    push ax
    push bx
    push cx
    push dx
    push si
    push di

    call draw_background

    xor si, si
rfs_coin_loop:
    mov bx, si
    shl bx, 1
    cmp word [coin_active + bx], 0
    je rfs_next_coin
    mov ax, [coin_x + bx]
    mov dx, [coin_y + bx]
    call draw_coin_circle
rfs_next_coin:
    inc si
    cmp si, 3
    jb rfs_coin_loop
    xor si, si
rfs_fuel_loop:
    mov bx, si
    shl bx, 1
    cmp word [fuel_active + bx], 0
    je rfs_next_fuel
    mov ax, [fuel_x + bx]
    mov dx, [fuel_y + bx]
    call draw_fuel_tank
rfs_next_fuel:
    inc si
    cmp si, 3
    jb rfs_fuel_loop
    call draw_all_blue_cars

    mov cx, [redx]
    mov dx, [redy]
    call draw_car_red

    call draw_fuel_hud
    call draw_coin_hud
    call draw_fuel_text

    pop di
    pop si
    pop dx
    pop cx
    pop bx
    pop ax
    ret


; show GAME OVER only
game_over_screen:
    pusha

    mov ah, 02h
    xor bh, bh
    mov dh, 12
    mov dl, 30
    int 10h

    mov ah, 0Eh
    mov bl, 0Ch
    mov si, msg_game_over

gos_line1:
    lodsb
    or al, al
    jz gos_line1_done
    int 10h
    jmp gos_line1
gos_line1_done:

    mov ah, 02h
    mov dh, 14
    mov dl, 24
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_press_key

gos_line2:
    lodsb
    or al, al
    jz gos_line2_done
    int 10h
    jmp gos_line2
gos_line2_done:

    popa
    ret


; final summary screen after game_over_screen
; shows name, roll, reason, and R/E choice
show_end_screen:
    pusha

    mov ax, VIDSEG
    mov es, ax

    ; draw box
    mov bx, 60
end_row:
    mov ax, bx
    mov cx, SCR_WIDTH
    mul cx
    add ax, 40
    mov di, ax
    mov cx, 240
    mov al, 1
    rep stosb
    inc bx
    cmp bx, 140
    jbe end_row

    ; "GAME SUMMARY"
    mov ah, 02h
    xor bh, bh
    mov dh, 8
    mov dl, 14
    int 10h
    mov ah, 0Eh
    mov bl, 0Eh
    mov si, msg_end_title
end_title:
    lodsb
    or al, al
    jz end_title_done
    int 10h
    jmp end_title
end_title_done:

    ; Name line
    mov ah, 02h
    mov dh, 11
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Ch
    mov si, msg_end_name
end_name_label:
    lodsb
    or al, al
    jz end_name_label_done
    int 10h
    jmp end_name_label
end_name_label_done:

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, player_name
end_name_value:
    lodsb
    or al, al
    jz end_name_value_done
    int 10h
    jmp end_name_value
end_name_value_done:

    ; Roll line
    mov ah, 02h
    mov dh, 13
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Eh
    mov si, msg_end_roll
end_roll_label:
    lodsb
    or al, al
    jz end_roll_label_done
    int 10h
    jmp end_roll_label
end_roll_label_done:

    mov ah, 0Eh
    mov bl, 0Fh
    mov si, player_roll
end_roll_value:
    lodsb
    or al, al
    jz end_roll_value_done
    int 10h
    jmp end_roll_value
end_roll_value_done:

    ; Reason line
    ; print "Reason: " at column 10
    mov ah, 02h
    xor bh, bh
    mov dh, 15
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_end_reason
end_reason_label:
    lodsb
    or al, al
    jz end_reason_label_done
    int 10h
    jmp end_reason_label
end_reason_label_done:

    ; move cursor to value column (aligned inside box)
    mov ah, 02h
    xor bh, bh
    mov dh, 15      ; same row
    mov dl, 18      ; fixed column for reason text
    int 10h

    mov ah, 0Eh
    mov bl, 0Fh

    mov al, [end_reason]
    cmp al, REASON_QUIT
    je end_reason_quit
    cmp al, REASON_FUEL
    je end_reason_fuel
    cmp al, REASON_CRASH
    je end_reason_crash
    mov si, msg_reason_unknown
    jmp end_reason_print

end_reason_quit:
    mov si, msg_reason_quit
    jmp end_reason_print
end_reason_fuel:
    mov si, msg_reason_fuel
    jmp end_reason_print
end_reason_crash:
    mov si, msg_reason_crash

end_reason_print:
end_reason_text:
    lodsb
    or al, al
    jz end_reason_text_done
    int 10h
    jmp end_reason_text
end_reason_text_done:

    ; options line
    mov ah, 02h
    mov dh, 18
    mov dl, 10
    int 10h
    mov ah, 0Eh
    mov bl, 0Fh
    mov si, msg_end_options
end_opt:
    lodsb
    or al, al
    jz end_opt_done
    int 10h
    jmp end_opt
end_opt_done:

end_wait_choice:
    mov ah, 0
    int 16h
    cmp al, 'r'
    je end_choice_retry
    cmp al, 'R'
    je end_choice_retry
    cmp al, 'e'
    je end_choice_exit
    cmp al, 'E'
    je end_choice_exit
    jmp end_wait_choice

end_choice_retry:
    popa
    mov al, 1
    ret

end_choice_exit:
    popa
    xor al, al
    ret


; RNG 0..BX-1
getrandom:
    push dx
    push cx
    cmp bx, 1
    ja gr_ok
    xor ax, ax
    jmp gr_exit
    
gr_ok:
    mov ah, 0
    int 1Ah
    mov ax, dx
    xor dx, dx
    div bx
    mov ax, dx
    
gr_exit:
    pop cx
    pop dx
    ret


spawn_lane db 0


; include car sprite FIRST
%include "redcar.inc"

car_sprite_end:

car_blue_sprite     equ car_sprite
car_blue_sprite_end equ car_sprite_end

sprite_bytes equ car_sprite_end - car_sprite

%macro tryw 1
    %if _carw = 0
        %if (sprite_bytes %% %1) = 0
            %assign _carw %1
        %endif
    %endif
%endmacro

%assign _carw 0

tryw 14
tryw 15
tryw 16
tryw 30
tryw 31
tryw 32

%if _carw = 0
    %error "Could not detect CARW"
%endif

CARW     equ _carw
CARH     equ sprite_bytes / CARW
CARHALFW equ (CARW/2)

move_cooldown  dw 0   ; movement delay timer

; include coin sprite 
%include "coin.inc"

; include fuel tank sprite (fueltank label)
%include "fueltank.inc"

; DATA SECTION

lane1      dw 0
lane2      dw 0
redx       dw 0
redy       dw 0
colstart   dw 0
colend     dw 0
lanec1     dw 0
lanec2     dw 0
lanec3     dw 0
xminc      dw 0
xmaxc      dw 0

blue_cars times (MAX_BLUE_CARS * 14) db 0

coin_base_x  dw 0
coin_base_y  dw 0

spawn_timer   dw 0

red_lane      db 0
red_left      dw 0
red_right     dw 0
red_top       dw 0
red_bottom    dw 0

game_over_flag dw 0

; helpers for side-lane collision (lane-change crash)
tmp_side_top      dw 0
tmp_side_bottom   dw 0
tmp_target_lane   db 0
tmp_side_flag     db 0

coin_active dw 0, 0, 0
coin_x     dw 0, 0, 0
coin_y     dw 0, 0, 0
coin_spawn_timer dw 0


fuel_tick:  dw 20   ; counts down, reduces fuel every time it hits 0
; fuel state
fuel_base_x      dw 0
fuel_base_y      dw 0

fuel_active      dw 0, 0, 0
fuel_x           dw 0, 0, 0
fuel_y           dw 0, 0, 0
fuel_spawn_timer dw 0

coin_count   dw 0
fuel_value   dw 12
digit_buf:    times 5 db 0

player_name:      db 0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0
player_name_len:  db 0

player_roll:      db 0,0,0,0,0,0,0,0,0,0,0
player_roll_len:  db 0

end_reason       db 0

msg_game_over      db 'GAME OVER',0
msg_press_key      db 'Press any key to continue',0

msg_title          db 'BITBLAZER',0
msg_start_prompt   db 'Press S to start',0
msg_start_prompt_blank db '               ',0
msg_confirm_exit   db 'Exit to DOS? (Y/N)',0
confirm_choice     db 0

msg_menu_play      db 'P - Play',0
msg_menu_exit      db 'E - Exit',0

msg_credit1        db '24L-0598 Hareem Ahmad',0
msg_credit2        db '24L-0575 Laiba Fida',0

msg_coins          db 'COINS: ',0
msg_fuel           db 'FUEL: ',0

; tutorial / input strings
msg_instr_title    db 'HOW TO PLAY',0
msg_left_line      db '[<]  Move Left',0
msg_right_line     db '[>]  Move Right',0
msg_up_line        db '[^]  Move Up',0
msg_down_line      db '[v]  Move Down',0

msg_collect_line   db 'Collect COINS to increase your score.',0
msg_fuel_line      db 'Movement costs FUEL - grab more before it runs out!',0

msg_arrow_brackets db '[ ]  [ ]  [ ]  [ ]',0

msg_press_s_base   db 'Press   to start',0

msg_info_title     db 'ENTER PLAYER INFO',0
msg_name_label     db 'Name:',0
msg_roll_label     db 'Roll No:',0

msg_end_title      db 'GAME SUMMARY',0
msg_end_name       db 'Name: ',0
msg_end_roll       db 'Roll: ',0
msg_end_reason     db 'Reason: ',0
msg_end_options    db 'R - Retry    E - Exit',0

msg_reason_quit    db 'You quit the game.',0
msg_reason_fuel    db 'You ran out of fuel.',0
msg_reason_crash   db 'You crashed into another car.',0
msg_reason_unknown db 'Game ended.',0
