         ;; Copyright 2020, Sjors van Gelderen

        ;; iNES header
        
        .inesprg 1              ; 1 bank of 16KB PRG-ROM
        .ineschr 1              ; 1 bank of 8KB CHR-ROM
        .inesmap 0              ; Mapper 0
        .inesmir 1              ; Background mirroring

	;; Push registers onto stack
PHR	.macro
	PHA
	TXA
	PHA
	TYA
	PHA
	.endm

	;; Pull registers from stack
PLR	.macro
	PLA
	TAY
	PLA
	TAX
	PLA
	.endm
	
	.rsset $0000
	
arg0			.rs 1
arg1			.rs 1
arg2			.rs 1
arg3			.rs 1
arg4			.rs 1
arg5			.rs 1
work0			.rs 1
work1			.rs 1
work2			.rs 1
work3			.rs 1
work4			.rs 1
work5			.rs 1
result0			.rs 1
result1			.rs 1
result2			.rs 1
result3			.rs 1
	
        .rsset $0010
	
game_started		.rs 1
game_dirty		.rs 1
sprite_count		.rs 1
sprite_zero_hit		.rs 1
	
fish_count		.rs 1
fish_data		.rs 12
fish_move_count         .rs 1
gem_count		.rs 1
gem_data		.rs 4

score 			.rs 2
level			.rs 1
level_data_offsets	.rs 8
level_scrolling		.rs 1

	.rsset $0050
player_x		.rs 1
player_y		.rs 1
player_dir		.rs 1
player_air		.rs 1
player_air_count 	.rs 1
player_swimming		.rs 1	
player_swim_count	.rs 1

bubble_x		.rs 1
bubble_y		.rs 1
bubble_state            .rs 1
bubble_count            .rs 1
theta                   .rs 1
theta_count             .rs 1
        
        ;; PRG-ROM bank

        .bank 0
        .org $C000
        
Reset:
        SEI                     ; Disable IRQs
        CLD                     ; Disable decimal mode
        LDX #$40
        STX $4017               ; Disable APU frame IRQ
        LDX #$FF
        TXS                     ; Set up stack
        INX
        STA $2000               ; Disable NMI
        STX $2001               ; Disable rendering
        STX $4010               ; Disable DMC IRQs

        JMP AwaitVerticalBlankDone
AwaitVerticalBlank:     
        BIT $2002               ; PPUSTATUS check for vertical blank
        BPL AwaitVerticalBlank
        RTS
AwaitVerticalBlankDone: 

        JSR AwaitVerticalBlank  ; First wait

	LDX #$00
ClearMemory:
        LDA #$00
        STA $0000,X
        STA $0100,X
        STA $0300,X
        STA $0500,X
        STA $0600,X
        STA $0700,X
        LDA #$FE
        STA $0200,X             ; Move all sprites off screen
        INX
        BNE ClearMemory
        
        JSR AwaitVerticalBlank  ; Second wait, PPU is ready after this

	
	;; ------------------------------------------------
	;; Initialize variables
	
	LDA #$20
	STA player_x
	LDA #$80
	STA player_y
	LDA #$01
	STA player_dir
	LDA #$00
	STA player_swimming
	LDA #$05
	STA player_swim_count
	LDA #$04
	STA player_air
	LDA #$00
	STA player_air_count

        LDA #$02
        STA fish_move_count
        
	LDA player_x
	STA bubble_x
	LDA player_y
	STA bubble_y
	LDA #$10
        STA bubble_count
        LDA #$00
        STA bubble_state
        STA theta
        STA theta_count

	LDA #$00
	STA level
	LDX #$00
	LDA #LOW(level_0)
	STA level_data_offsets,X
	INX
	LDA #HIGH(level_0)
	STA level_data_offsets,X
	INX
	LDA #LOW(level_1)
	STA level_data_offsets,X
	INX
	LDA #HIGH(level_1)
	STA level_data_offsets,X
	INX
	LDA #LOW(level_2)
	STA level_data_offsets,X
	INX
	LDA #HIGH(level_2)
	STA level_data_offsets,X
	INX
	LDA #LOW(level_3)
	STA level_data_offsets,X
	INX
	LDA #HIGH(level_3)
	STA level_data_offsets,X
        INX
        LDA #LOW(level_4)
        STA level_data_offsets,X
        INX
        LDA #HIGH(level_4)
        STA level_data_offsets,X
	LDA #$FF
	STA level_scrolling

	LDA #$00
	STA game_started
	STA game_dirty
	STA sprite_count
	STA sprite_zero_hit

	LDA #$00
	STA score

	;; ------------------------------------------------


	;; ------------------------------------------------
	;; Loads all palettes into the PPU
	
LoadPalettes:
        LDA $2002               ; Reset high/low latch on PPU
        LDA #$3F
        STA $2006               ; Write high byte of $3F00
        LDA #$00
        STA $2006               ; Write low byte of $3F00
        LDX #$00
.Loop:
        LDA palettes,X
        STA $2007               ; Write to PPU
        INX
        CPX #$20
        BNE .Loop
LoadPalettesDone:

	;; ------------------------------------------------
	

	;; ------------------------------------------------
	;; Draws a full screen of metatiles
	;; arg0  - Left or right screen
	;; work0 - Metatile nametable progress
	;; work1 - Even or odd line
	;; work2 - Line progress

	LDA #$00		; Draw first two screens
	STA arg0
	JSR DrawScreen	
	INC arg0
	JSR DrawScreen
	JMP DrawScreenDone
	
DrawScreen:
	PHR
	
	LDA #$00
	STA work0
	STA work1
	STA work2

	LDA $2002		; Reset PPU latch
	LDA arg0
	BNE .SkipLeftScreen
	LDA #$20		; Top left of left screen
	JMP .SkipRightScreen
.SkipLeftScreen:
	LDA #$24		; Top left of right screen

	
.SkipRightScreen:
	STA $2006
	LDA #$00
	STA $2006

.LineLoop:
	LDA work0		; Get the metatile nametable progress
	CLC
	ADC work2		; Add the line progress
	TAX
	LDA lvl_1_nt,X		; Get the metatile index
	TAX
	LDY work1		; Add top or bottom of metatile
	CPY #$00
	BNE .Odd
	LDA metatiles_topleft,X
	STA $2007
	LDA metatiles_topright,X
	STA $2007
	JMP .SkipOdd
.Odd:
	LDA metatiles_bottomleft,X
	STA $2007
	LDA metatiles_bottomright,X
	STA $2007
.SkipOdd:

	INC work2		; Increment line progress
	LDA work2
	CMP #$10
	BNE .LineLoop
	
	LDA #$00
	STA work2		; Reset the line progress
	INC work1		; Switch to odd line
	LDA work1
	CMP #$02
	BNE .LineLoop
	
	LDA #$00		; Switch to even line
	STA work1		
	LDA work0		; Update metatile nametable progress with a full line
	CLC
	ADC #$10		
	STA work0
	CMP #$F0		; Check if we've completed all lines
	BNE .LineLoop

	PLR
	RTS
DrawScreenDone:
	
	;; ------------------------------------------------

		
	;; ------------------------------------------------
	;; Loads all attributes and sends them to the PPU
	;; arg0 - Nametable to provide attributes for

	LDA #$00
	STA arg0
	JSR LoadAttributes
	INC arg0
	JSR LoadAttributes
	JMP LoadAttributesDone
	
LoadAttributes:
	PHR
	
        LDA $2002		; Reset PPU latch
	LDA arg0
	BNE .SkipNametable0
        LDA #$23		; Nametable 0 attributes address
	JMP .SkipNametable1
.SkipNametable0:
	LDA #$27		; Nametable 1 attributes address
.SkipNametable1:
	STA $2006
        LDA #$C0
        STA $2006
	
        LDX #$00
.Loop:
        LDA lvl_1_at,X
        STA $2007
        INX
        CPX #$40
        BNE .Loop
	
	PLR
	RTS
LoadAttributesDone:

	;; ------------------------------------------------


	;; ------------------------------------------------
	;; LoadLevel
	;; arg0           - Level to load
	;; work0 -> work1 - Level addresses memory location
	;; work2          - Indicator for amount of data to load
	;; work3          - Counter

	LDA level
	STA arg0
	JSR LoadLevel
	
	JMP LoadLevelDone

LoadLevel:
	PHR

	INC level_scrolling
	
	LDX #$FF
	LDY #$FE		; Get the correct address information
.Loop0:
	INX
	INY
	INY
	CPX arg0
	BNE .Loop0

	LDA level_data_offsets,Y 	; Store that information for lookup
	STA work0
	INY
	LDA level_data_offsets,Y
	STA work1
	
	LDY #$00
	LDA [work0],Y
	STA fish_count
	STA work2
	INY
	LDA #$00
	STA work3		; Loop iteration counter
	LDX #$00
.Loop1:
	LDA [work0],Y
	STA fish_data,X	
	INY
	INX
	INC work3
	LDA work3
	CMP #$03
	BNE .Loop1
	LDA #$00
	STA work3
	DEC work2
	LDA work2
	BNE .Loop1
	
	LDA [work0],Y
	STA gem_count
	STA work2
	INY
	LDX #$00
	LDA #$00
	STA work3
.Loop2:
	LDA [work0],Y
	STA gem_data,X
	INX
	INY
	INC work3
	LDA work3
	CMP #$02
	BNE .Loop2
	LDA #$00
	STA work3
	DEC work2
	LDA work2
	BNE .Loop2
	
	PLR
	RTS
	
LoadLevelDone:
	
	;; ------------------------------------------------
	

	;; ------------------------------------------------
	;; Checks for collision based on two points and a distance
	;; arg0 -> arg1 - Point 0
	;; arg2 -> arg3 - Point 1
	;; arg4         - Distance
	;; work0        - Coord 0
	;; work1        - Coord 1
	;; work2        - Distance for overflow

	JMP CheckCollisionDone

CheckCollision:
	PHR
	
	LDA #$00
	STA result0
	LDX #$00

	LDA #$FF
	SEC
	SBC arg4
	STA work2
	
	LDA arg0
	STA work0
	LDA arg2
	STA work1
	
.Loop:
	LDA work1
	SEC
	SBC work0
	BCC .Overflow
	CMP arg4
	BCS .Finish		; No hit
	JMP .SkipOverflow
.Overflow:
	CMP work2
	BCC .Finish		; No hit
.SkipOverflow:
	LDA arg1
	STA work0
	LDA arg3
	STA work1
	INX
	CPX #$02
	BNE .Loop
	INC result0		; Hit!

.Finish:
	PLR
	RTS
	
CheckCollisionDone
	
	;; ------------------------------------------------

	
	;; ------------------------------------------------
	;; Adds a single point

	JMP AddPointDone

AddPoint:	
	PHR

	INC score
	LDA score
	CMP #$0A
	BNE .Finish
	LDA #$00
	STA score
	LDX #$01
	INC score,X
	LDA score,X
	CMP #$0A
	BNE .Finish
	LDA #$00
	STA score,X
	
.Finish:
	PLR
	RTS
AddPointDone:	

	;; ------------------------------------------------
	
	
	;; ------------------------------------------------
	;; Updates the gems

	JMP UpdateGemsDone

UpdateGems:	
	PHR

	LDA player_x
	STA arg2
	LDA player_y
	STA arg3
	LDA #$09
	STA arg4
	
	LDX #$00
	LDY #$00
.Loop:
	LDA gem_data,X
	STA arg0
	INX
	LDA gem_data,X
	STA arg1
	JSR CheckCollision
	LDA result0
	BEQ .SkipPickup
	LDA #$F0
	STA gem_data,X
	DEX
	STA gem_data,X
	INX
	JSR AddPoint
.SkipPickup:
	INX
	INY
	CPY gem_count
	BNE .Loop
	
	PLR
	RTS
UpdateGemsDone:	
	
	;; ------------------------------------------------

	
	;; ------------------------------------------------
	;; Moves the fish
	;; arg0  - x coord
	;; arg1  - speed
	;; work0 - actual speed
	;; result0 - new x coord
	;; result1 - new speed

	JMP MoveFishDone

MoveFish:
	PHR

        LDA arg0
        STA result0
        LDA arg1
        STA result1
        
        LDA fish_move_count
        BNE .Finish
        
	LDA arg0
	STA result0
	LDA arg1
	STA result1
	AND #%01111111		; Get speed without direction
	STA work0	
	LDA arg1
	AND #%10000000		; Check direction
	BNE .SkipMoveLeft	
	LDA result0	
	SEC
	SBC work0		; Move left
	STA result0
        ;; CMP #$08
        CMP #$20
	BCS .Finish
	LDA arg0		; Overflow, restore x
	STA result0
	LDA work0
	ORA #%10000000		; Set direction bit
	STA result1
	JMP .Finish
.SkipMoveLeft:
	LDA result0
	CLC
	ADC work0		; Move right
	STA result0
        CMP #$E8
	BCC .Finish
	LDA arg0		; Overflow, restore x
	STA result0
	LDA work0		; Unset direction bit	
	STA result1

.Finish:
	PLR
	RTS
MoveFishDone:	

	;; ------------------------------------------------
	

	;; ------------------------------------------------
	;; Updates the fish
	;; work0 - y coord
	
	JMP UpdateFishDone
	
UpdateFish:
	PHR

        DEC fish_move_count
        
	LDA player_x
	STA arg2
	LDA player_y
	STA arg3
	LDA #$09
	STA arg4
	
	LDX #$00
	LDY #$00
.Loop:	
	LDA fish_data,X		; Get X coord
	STA arg0
	INX
	LDA fish_data,X		; Get Y coord
	STA work1		; work0 is used by MoveFish
	INX
	LDA fish_data,X		; Get speed
	STA arg1
	JSR MoveFish
	LDA result1
	STA fish_data,X	
	DEX
	DEX
	LDA result0
	STA fish_data,X

	LDA work1
	STA arg1	
	JSR CheckCollision
	LDA result0
	BEQ .SkipLose
	LDA #$00
	STA player_air
.SkipLose:
	
	INX
	INX
	INX
	INY
	CPY fish_count
	BNE .Loop

        LDA fish_move_count
        BNE .SkipResetMoveCount
        LDA #$02
        STA fish_move_count
.SkipResetMoveCount:
	PLR
	RTS
	
UpdateFishDone:	
	
	;; ------------------------------------------------


	;; ------------------------------------------------
	;; Updates the player

	JMP UpdatePlayerDone

UpdatePlayer:
	PHR

	LDA player_air
	BNE .Alive
	LDA player_y
        CMP #$C2
	;; BEQ .Finish
	BEQ .TemporaryJumpToFinish
	INC player_y
        INC player_y
	;; JMP .Finish
	JMP .TemporaryJumpToFinish
.Alive:
	
	LDA player_swim_count
	CMP #$05
	BCS .SkipSwim
	INC player_swim_count
.SkipAllowSwim:
	
	LDA player_y
	SEC
	SBC #$05
	STA player_y
	LDA player_dir
	BNE .SkipSwimLeft
	LDA player_x
        CMP #$20
	BCC .SkipSwim
	SEC
	SBC #$05
	STA player_x
	JMP .SkipSwim
.SkipSwimLeft:
	LDA player_x
	CLC
	ADC #$05
	STA player_x
	CMP #$F0
	BCC .SkipSwim
	INC level
	LDA level
	CMP level_count
	BNE .SkipLoopLevels
	LDA #$00
	STA level
.SkipLoopLevels:
	STA arg0
	JSR LoadLevel
	LDA #$01
	STA game_started
        LDA #$20
	STA player_x
	
	JMP .SkipTemporaryJumpToFinish
.TemporaryJumpToFinish:
	JMP .Finish
.SkipTemporaryJumpToFinish:
	
.SkipSwim:
	LDA player_y
        CMP #$B4
	BCS .SkipSink
	INC player_y
.SkipSink:
	LDA player_y
        CMP #$34
	BCS .NotBreathing
        LDA #$34
	STA player_y
	LDA #$04
	STA player_air
	LDA #$00
	STA player_air_count
	JMP .SkipBreathing
.NotBreathing:
	INC player_air_count
	LDA player_air_count
	CMP #$F0
	BNE .SkipBreathing
	LDA level_scrolling
	BNE .SkipBreathing
	LDA game_started
	BEQ .SkipBreathing
	DEC player_air
	LDA #$00
	STA player_air_count
.SkipBreathing:

.Finish:
	PLR
	RTS

UpdatePlayerDone:	

	;; ------------------------------------------------
	
	
	;; ------------------------------------------------
	;; Draws the air meter

	JMP DrawAirMeterDone
	
DrawAirMeter:
	PHR
	
	LDA $2002
	;; LDA #$28
	LDA #$20
	STA $2006
	;; LDA #$46
        LDA #$86
	STA $2006

	LDX #$FF
.Loop:
	INX
	
	CPX player_air
	BCC .LoadAirTile
	LDA #$45
	JMP .SkipLoadAirTile
.LoadAirTile:
	LDA #$26
.SkipLoadAirTile:
	
	STA $2007
	CPX #$03
	BNE .Loop

	PLR
	RTS
DrawAirMeterDone:	
	
	;; ------------------------------------------------

	
	;; ------------------------------------------------
	;; Draws the score

	JMP DrawScoreDone
	
DrawScore:
	PHR
	
	LDA $2002
	LDA #$20
	STA $2006
        LDA #$9C
	STA $2006

	LDX #$01
	LDA score,X
	STA $2007
	LDA score
	STA $2007

	PLR
	RTS
DrawScoreDone:
	
	;; ------------------------------------------------


	;; ------------------------------------------------
	;; Hides the logo
	;; arg0           - Which nametable to remove the logo from
	;; work0 -> work1 - PPU address

	LDA #$01
	STA arg0
	JSR HideLogo
	JMP HideLogoDone
	
HideLogo:
	PHR

	LDA $2002		; Reset PPU latch
	LDA arg0
	BNE .SkipNametable0
	LDA #$21	
	JMP .SkipNametable1
.SkipNametable0:
	LDA #$2D
.SkipNametable1:
	STA $2006
	STA work0		; Remember high byte
	LDA #$0A
	STA $2006
	STA work1		; Remember low byte
	
	LDX #$00
	LDY #$00

.Loop0:
	LDA #$32
	STA $2007
	INX
	CPX #$0C
	BNE .Loop0
	LDA $2002		; Reset PPU latch
	LDA work0
	STA $2006
	LDA work1
	CLC
	ADC #$20
	STA $2006
	STA work1
	LDX #$00
	INY
	CPY #$04
	BNE .Loop0
	
	PLR
	RTS
HideLogoDone:
	
	;; ------------------------------------------------
	
	
	;; ------------------------------------------------
	;; arg0 -> arg1 - Sprite address
	;; arg2 -> arg3 - Sprite position
	;; arg4         - Attribute bits to set
	;; work0        - Actor sprite amount
	;; work1        - Actor half width
	
	JMP PrepareSpritesDone
	
PrepareSprites:
	PHR

	LDY #$01
	LDA [arg0],Y		; Retrieve actor width
	LSR A			; Halve the width
        STA work1

	LDX sprite_count
	LDY #$00
	LDA [arg0],Y		; Get the amount of sprites for the actor
	STA work0
	INY
	INY
	
.Loop:
	LDA [arg0],Y		; Get sprite y offset
	CLC
	ADC arg3		; Add actor y coordinate
        SEC
        SBC work1               ; Center
	STA $0200,X
	INY
	INX

	LDA [arg0],Y		; Tile
	STA $0200,X
	INY
	INX
	
	LDA [arg0],Y		; Attributes
	ORA arg4		; Set any provided attribute bits
	STA $0200,X
	INY
	INX
                
	LDA arg4		; Check if actor should be flipped
	BEQ .SkipFlip
        LDA arg2                ; Get actor x position
        CLC
        ADC work1               ; Get actor right border x
        SEC                     
        SBC [arg0],Y            ; Correct for sprite offset
        SEC
        SBC #$08                ; Correct for sprite size
	JMP .XDone
.SkipFlip:
        LDA arg2                ; Get actor x position
        CLC
        ADC [arg0],Y            ; Add sprite x offset
        SEC
        SBC work1               ; Center
.XDone:
	STA $0200,X
	INY
	INX

	LDA sprite_count
	CLC
	ADC #$04
	STA sprite_count

	CPY work0
	BNE .Loop
	
	PLR
	RTS
PrepareSpritesDone:
	
	;; ------------------------------------------------

	
	;; ------------------------------------------------
	;; Cleans up unused sprites
	
	JMP ClearSpritesDone

ClearSprites:
	PHR

	LDX sprite_count
        LDY #$00
.Loop:
        LDA #$FE
        INY
        CPY #$03
        BNE .SkipAttribute
        LDA #$20                ; Hide sprite behind background, does not work yet
        LDY #$00
.SkipAttribute:
	STA $0200,X
	INX
	CPX #$00
	BNE .Loop
	
	PLR
	RTS
ClearSpritesDone:

	;; ------------------------------------------------

	
	;; ------------------------------------------------
	;; Reads controller input
	;; work0 - Player movement input detected

	JMP ReadControllerDone

ReadController:
	PHR
	
	LDA #$01		; Start reading
	STA $4016
	LDA #$00
	STA $4016

	LDX #$00
	
	LDA $4016
	AND #$01
	BEQ .NotA
	INX
.NotA:
	
	LDA $4016
	AND #$01
	BEQ .NotB
	INX
.NotB:
	
	CPX #$00
	BEQ .NotAB
	
	LDA player_air
	BEQ .SkipAB
	
	LDA player_swimming
	BNE .SkipAB
	
	LDA #$01
	STA player_swimming
	
	LDA #$00
	STA player_swim_count
	
	JMP .SkipAB
	
.NotAB:
	LDA #$00
	STA player_swimming
.SkipAB:
	
	LDA $4016
	AND #$01
	BEQ .NotSelect

	;; Select logic

.NotSelect:
	LDA $4016
	AND #$01
	BEQ .NotStart

	;; Start logic
        LDA player_air
        BNE .SkipReset
        JMP Reset
.SkipReset:
	
.NotStart:
	LDA $4016
	AND #$01
	BEQ .NotUp

	;; Up logic
	
.NotUp:
	LDA $4016
	AND #$01
	BEQ .NotDown

	;; Down logic
	
.NotDown:
	LDA $4016
	AND #$01
	BEQ .NotLeft

        LDA player_air
        BEQ .NotLeft
        
	LDA #$00
	STA player_dir

.NotLeft:
	LDA $4016
	AND #$01
	BEQ .NotRight

        LDA player_air
        BEQ .NotRight
        
	LDA #$01
	STA player_dir

.NotRight:
	
	PLR
	RTS
ReadControllerDone:	
	
	;; ------------------------------------------------

        LDA #%10010000          ; Enable NMI, sprites from pattern table 0
        STA $2000               ; Background from pattern table 1
        LDA #%00011110          ; Enable sprites, background
        STA $2001
	
Forever:
	LDA game_dirty
	BEQ Forever		; Wait for NMI to occur
	LDA level_scrolling
	
	JSR ReadController

	LDA level_scrolling
	BNE .SkipUpdates

        LDA bubble_y
        CMP #$14
        BCC .SkipResetTheta
        
        INC theta_count
        LDA theta_count
        CMP #$06
        BNE .SkipResetTheta
        LDA #$00
        STA theta_count
        INC theta
        LDA theta
        CMP sine
        BNE .SkipResetTheta
        LDA #$00
        STA theta
.SkipResetTheta:
        
	JSR UpdatePlayer
	JSR UpdateFish
	JSR UpdateGems
	
.SkipUpdates:
	
	LDA #$00
	STA sprite_count

	;; ------------------------------------------------

DrawSpriteZero:
	LDA #LOW(sprite_zero)
	STA arg0
	LDA #HIGH(sprite_zero)
	STA arg1
	LDA #$80
	STA arg2
        LDA #$2E
	STA arg3
	LDA #$20
	STA arg4
	JSR PrepareSprites
	
DrawSpriteZeroDone:

	;; ------------------------------------------------

DrawPlayer:
	LDA level_scrolling
	BNE DrawPlayerDone
	
	LDA player_air
	BNE .SkipSinkFrame
	LDA #LOW(player_sprite_2)
	STA arg0
	LDA #HIGH(player_sprite_2)
	STA arg1
	JMP .Draw
.SkipSinkFrame:
	LDA player_swim_count
	CMP #$05
	BCS .SkipSwimFrame
	LDA #LOW(player_sprite_1)
	STA arg0
	LDA #HIGH(player_sprite_1)
	STA arg1
	JMP .Draw
.SkipSwimFrame:
	LDA #LOW(player_sprite_0)
	STA arg0
	LDA #HIGH(player_sprite_0)
	STA arg1
.Draw:
	LDA player_x
	STA arg2
	LDA player_y
	STA arg3
	LDA #$00
	LDX player_dir
	BNE .SkipFlip
	ORA #%01000000
.SkipFlip:
	STA arg4
	JSR PrepareSprites

DrawPlayerDone:	

	;; ------------------------------------------------

DrawFish:
	LDA level_scrolling
	BNE DrawFishDone
	
	LDA #LOW(fish_sprite)
	STA arg0
	LDA #HIGH(fish_sprite)
	STA arg1
	LDX #$00
	LDY #$00
.DrawFishLoop:
	LDA #$00
	STA arg4
	LDA fish_data,X
	STA arg2
	INX
	LDA fish_data,X
	STA arg3
	INX
	LDA fish_data,X
	INX
	INY
	AND #%10000000
	BNE .SkipFlip
	LDA #%01000000
	STA arg4
.SkipFlip:
	JSR PrepareSprites
	CPY fish_count
	BNE .DrawFishLoop

DrawFishDone:	

	;; ------------------------------------------------

DrawGems:
	LDA level_scrolling
	BNE DrawGemsDone
	
	LDA #LOW(gem_sprite)
	STA arg0
	LDA #HIGH(gem_sprite)
	STA arg1
	LDX #$00
	LDY #$00
.DrawGemsLoop:
	LDA gem_data,X
	STA arg2
	INX
	LDA gem_data,X
	STA arg3
	INX
	INY
	LDA #$00
	STA arg4
	JSR PrepareSprites
	CPY gem_count
	BNE .DrawGemsLoop

DrawGemsDone:	

	;; ------------------------------------------------

DrawBubble:
        LDA level_scrolling
        BNE .DrawBubbleDoneBridge

        ;; State 0
        LDA bubble_state
        BNE .Not0
        
        DEC bubble_count
        BNE .DrawBubbleDoneBridge

        LDA sine
        LSR A
        STA theta
        LDA player_dir
        BEQ .SkipLeft
        LDA player_x
        CLC
        ADC #$08
        JMP .SkipRight
.SkipLeft:
        LDA player_x
        SEC
        SBC #$08
.SkipRight:
        STA bubble_x
        LDA player_y
        STA bubble_y
        
        LDA #$10
        STA bubble_count
        INC bubble_state
        JMP DrawBubbleDone
.Not0:
        
        CMP #$01
        BNE .Not1

        ;; State 1
        DEC bubble_y
        LDA #LOW(bubble_sprite_0)
        STA arg0
        LDA #HIGH(bubble_sprite_0)
        STA arg1
        DEC bubble_count
        BNE .Finish
        INC bubble_state
.Not1:

        JMP .SkipDrawBubbleDoneBridge
.DrawBubbleDoneBridge:
        JMP DrawBubbleDone
.SkipDrawBubbleDoneBridge:        
        
        CMP #$02
        BNE .Not2
        
        ;; State 2
        DEC bubble_y
        LDA #LOW(bubble_sprite_1)
        STA arg0
        LDA #HIGH(bubble_sprite_1)
        STA arg1
        LDA bubble_y
        CMP #$20
        BCS .Finish
        LDA #$10
        STA bubble_count
        INC bubble_state
.Not2:

        CMP #$03
        BNE .Not3

        ;; State 3
        LDA #LOW(bubble_sprite_2)
        STA arg0
        LDA #HIGH(bubble_sprite_2)
        STA arg1
        DEC bubble_count
        BNE .Finish
        LDA #$D0
        STA bubble_count
        LDA #$00
        STA bubble_state
.Not3:

.Finish:
        LDA bubble_state
        BEQ DrawBubbleDone

        LDA bubble_x
        LDX bubble_state
        CPX #$02
        BNE .SkipSine
        LDA sine
        LSR A
        STA work0               ; TODO: Check if safe
        LDA theta
        TAX
        INX
        CMP work0
        BCC .SkipSubtract
        LDA bubble_x
        SEC
        SBC sine,X
        JMP .SkipAdd
.SkipSubtract:
        LDA bubble_x
        CLC
        ADC sine,X
.SkipAdd:
        LDA bubble_x
        LDX theta
        INX
        CLC
        ADC sine,X
.SkipSine:

        STA arg2
        LDA bubble_y
        STA arg3
        LDA #$00
        STA arg4
        JSR PrepareSprites

DrawBubbleDone: 
	
	;; ------------------------------------------------

	JSR ClearSprites
	
	LDA #$00
	STA game_dirty
        JMP Forever		; Wait for NMI to occur
        
NMI:
	PHR
	
	LDA #$01
	STA game_dirty

	JSR DrawAirMeter
	JSR DrawScore
	
        LDA #$00		; Sprite transfer
        STA $2003               ; Set the low byte of the RAM address
        LDA #$02
        STA $4014               ; Set the high byte of the RAM address and start the transfer

        LDA #%10010000          ; Reset default PPU mask values
        STA $2000
        LDA #%00011110
        STA $2001

	LDA level_scrolling	
	BEQ .SkipScrolling
	CLC
	ADC #$05
	BCC .SkipOverflow
        LDA #$10
        STA bubble_count
        LDA #$00
        STA bubble_state
	STA arg0
	JSR HideLogo
        LDA #$00
.SkipOverflow:
	STA level_scrolling
.SkipScrolling:

	LDA $2002
	LDA #$00
	STA $2005
	STA $2005
	
	LDA sprite_count	; Don't wait for sprite 0 if there aren't any sprites on the screen yet
	BEQ .SkipSpriteZeroHit

.SpriteZeroClearWait:
	BIT $2002
	BVS .SpriteZeroClearWait
	
.SpriteZeroWait:
	BIT $2002
	BVC .SpriteZeroWait
	
	LDA level_scrolling
        STA $2005
	LDA #$00		; No vertical scrolling
	STA $2005
.SkipSpriteZeroHit:
	
	PLR
        RTI

	;; ------------------------------------------------

        .bank 1
        .org $E000

sine:
        .db $08
        .db $00, $03, $06, $08
        .db $09, $08, $06, $03
        
level_count:
	.db $05
	
level_0:
	.db $01			; Fish data
	.db $FE, $FE, $00	
	.db $01			; Gem data
	.db $A0, $A0	
	
level_1:
	.db $01			; Fish data
	.db $D0, $47, $01	
	.db $01			; Gem data
	.db $5F, $5F		
	
level_2:
	.db $03			; Fish data
	.db $A0, $47, $01	
	.db $B0, $80, $03
	.db $A4, $A2, $02
	.db $02			; Gem data
	.db $5F, $40		
	.db $80, $90
	
level_3:
	.db $04			; Fish data
	.db $A0, $57, $01	
	.db $B0, $80, $03
	.db $A4, $96, $02
	.db $A0, $AB, $02
	.db $02			; Gem data
	.db $80, $40		
	.db $40, $90

level_4:
        .db $03
        .db $96, $30, $03
        .db $A0, $40, $03
        .db $8F, $60, $03
        .db $01
        .db $50, $70

	;; TODO: Consider using only one attribute byte per sprite
player_sprite_0:
	.db $22			; 8 sprites, 4 bytes per sprite, 2 byte offset
	.db $20			; 4 sprites wide
	.db $00, $52, $00, $10
	.db $08, $60, $00, $00
	.db $08, $61, $00, $08
	.db $08, $62, $00, $10
	.db $08, $63, $00, $18
	.db $10, $70, $00, $00
	.db $10, $71, $00, $08
	.db $18, $81, $00, $08

player_sprite_1:
	.db $22
	.db $20
	.db $00, $56, $00, $10
	.db $00, $57, $00, $18
	.db $08, $65, $00, $08
	.db $08, $66, $00, $10
	.db $10, $74, $00, $00
	.db $10, $75, $00, $08
	.db $10, $76, $00, $10
	.db $18, $84, $00, $00

player_sprite_2:
	.db $1A
	.db $20
	.db $00, $90, $00, $00
	.db $00, $91, $00, $08
	.db $00, $92, $00, $10
	.db $00, $93, $00, $18
	.db $08, $A1, $00, $08
	.db $08, $A2, $00, $10
	
fish_sprite:
	.db $12
	.db $10
	.db $00, $02, $01, $00
	.db $00, $03, $01, $08
	.db $08, $12, $01, $00
	.db $08, $13, $01, $08

gem_sprite:
	.db $12
	.db $10
	.db $00, $00, $02, $00
	.db $00, $01, $02, $08
	.db $08, $10, $02, $00
	.db $08, $11, $02, $08

bubble_sprite_0:
	.db $06
	.db $08
	.db $00, $42, $01, $00
	
bubble_sprite_1:
	.db $06
	.db $08
	.db $00, $43, $01, $00
	
bubble_sprite_2:
	.db $06
	.db $08
	.db $00, $44, $01, $00

sprite_zero:
	.db $06
	.db $08
	.db $00, $FF, $00, $00
	
metatiles_topleft:
        .incbin "graphics.mttl"
	
metatiles_topright:
        .incbin "graphics.mttr"
	
metatiles_bottomleft:
        .incbin "graphics.mtbl"

metatiles_bottomright:
	.incbin "graphics.mtbr"

lvl_1_nt:
        .incbin "level_1.nt"

lvl_1_at:
        .incbin "level_1.at"
        
palettes:
        .incbin "graphics.s"
        
        .org $FFFA              ; IRQ vectors defined here
        .dw NMI
        .dw Reset
        .dw 0

        ;; CHR-ROM bank

        .bank 2
        .org arg0
        .incbin "graphics.chr"
