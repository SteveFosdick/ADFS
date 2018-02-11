ORG &8000
CPU 1


;;                     ACORN ADFS 1.50 ROM DISASSEMBLY
;;                     ===============================
;;                   ADFS CODE COPYRIGHT ACORN COMPUTERS
;;
;;               DISASSEMBLY COMMENTARY COPYRIGHT J.G.HARSTON
;;               ============================================
;;
;; ROM HEADER
;; ==========
       EQUB &00,&00,&00 ;; No language entry
       JMP L9ACE        ;; Jump to service handler
       EQUB &82         ;; Service ROM, 6502 code
       EQUB &17         ;; Offset to (C)
IF PATCH_SD
       EQUB &57         ;; Binary version number
ELIF PATCH_IDE
       EQUB &53         ;; Binary version number
ELSE
       EQUB &50         ;; Binary version number
ENDIF
       EQUS "Acorn ADFS" ;;ROM Title
       EQUB &00
IF PATCH_SD
       EQUS "157"       ;; Version string
ELIF PATCH_IDE
       EQUS "153"       ;; Version string
ELSE
       EQUS "150"       ;; Version string
ENDIF
       EQUB &00         ;; Copyright string
       EQUS "(C)1984"
       EQUB &00
IF TEST_SHIFT
       EQUB &A9
ENDIF
;;
;;
;; Claim Tube if present
;; ---------------------
.L8020 LDY #&04
       BIT &CD
       BPL L8039        ;; Exit with no Tube present
.L8026 LDA (&B0),Y      ;; Copy address to &C227-2A
       STA ABSWS+&0226,Y
       DEY
       BNE L8026
       LDA #&40
       TSB &CD          ;; Flag Tube being used
.L8032 LDA #&C4         ;; ADFS Tube ID=&04, &C0=Claim
       JSR &0406        ;; Claim Tube
       BCC L8032        ;; Loop until claim successful
.L8039 RTS
;;
;; Release Tube if used, and restore Screen settings
;; -------------------------------------------------
.TUBE_RELEASE
.L803A BIT &CD
       BVC L8047        ;; Tube not being used
       LDA #&84         ;; ADFS Tube ID=&04, &80=Release
       JSR &0406        ;; Release Tube
       LDA #&40
       TRB &CD          ;; Reset Tube being used flag
.L8047
IF SHADOW_SCREEN
       LDA ABSWS+&02D7  ;; Screen memory used?
       BEQ L804F        ;; Exit if screen unchanged
       STA &FE34        ;; Restore screen setting
ENDIF
.L804F STZ ABSWS+&02D7  ;; Clear screen flag
       RTS
;;
;; Check for screen memory
;; -----------------------
;; Put shadow screen memory into main memory if i/o address specifies &FFFExxxx
;;
IF SHADOW_SCREEN
.L8053
       PHY              ;; Save Y
       LDY &FE34        ;; Get current Screen setting
       STY ABSWS+&02D7  ;; Save it
       INX              ;; Address=&FFxxxxxx?
       BNE L806D        ;; Not I/O memory, exit
       CMP #&FE         ;; Address=&FFFExxxx?
       BNE L806D        ;; Not screen memory, exit
       TYA              ;; Get current screen state into A
       ROR A            ;; Move to Cy
       LDA #&04
       TRB &FE34        ;; Put normal RAM in memory
       BCC L806D        ;; Exit if shadow screen being displayed
       TSB &FE34        ;; Put shadow RAM in memory
.L806D PLY              ;; Restore Y
       RTS

       MACRO SHADOW_SELECT
       JSR   L8053
       ENDMACRO
ELSE
       MACRO SHADOW_SELECT
       ENDMACRO
ENDIF
;;
;;
;; DRIVE ACCESS ROUTINES
;; =====================
;; This is the SCSI subsystem. Access to drives 4 to 7 access floppy
;; drives 0 to 3 with the 1770 FDC. Access to drives 0 to 3 access
;; SCSI devices 0 to 3 if a SCSI interface is present. If there is
;; no SCSI interface, access to drives 0 to 3 accesses floppy drives
;; 0 to 3.
;;
;; Read hard drive status. Waits for status value to settle before returning
;; -------------------------------------------------------------------------
IF PATCH_SD
;; Drive status is not used in the SD Code
ELIF PATCH_IDE
.L806F PHP
.L8070 LDA &FC47        ;; Get IDE status
       STA &CC          ;; Save this value
       LDA &FC47        ;; Get ISE status
       CMP &CC          ;; Compare with previous status
       BNE L8070        ;; Loop until status stays same
       PLP
       RTS
ELSE
.L806F PHP
.L8070 LDA &FC41        ;; Get SCSI status
       STA &CC          ;; Save this value
       LDA &FC41        ;; Get SCSI status
       CMP &CC          ;; Compare with previous status
       BNE L8070        ;; Loop until status stays same
       PLP
       RTS
ENDIF
;;
;; Set SCSI to command mode
;; ------------------------
IF PATCH_SD
.L807E RTS
.ReadBreak
       JSR L9A88
       AND #&01
       RTS
.MountCheck
       JSR LA19E        ;; Do *MOUNT, then reselect ADFS
       JMP L9B4A
ELIF PATCH_IDE
.L807E RTS
       NOP
       NOP
       NOP
       RTS
.ReadBreak
       JSR L9A88
       AND #&01
       RTS
.WaitForData
       LDA &FC47        ;;  Loop until data ready
       BIT #8
       BEQ WaitForData
       RTS
.MountCheck
       JSR LA19E        ;; Do *MOUNT, then reselect ADFS
       JMP L9B4A
       EQUB &F9         ;; Junk - so a binary compare will pass
ELSE
.L807E LDY #&00         ;; Useful place to set Y=0
.L8080 LDA #&01
       PHA              ;; Save data value
.L8083 JSR L806F        ;; Get SCSI status
       AND #&02         ;; BUSY?
       BNE L8083        ;; Loop until not BUSY
       PLA              ;; Get data value back
       STA &FC40        ;; Write to SCSI data
       STA &FC42        ;; Write to SCSI select to strobe it
.L8091 JSR L806F        ;; Get SCSI status
       AND #&02         ;; BUSY?
       BEQ L8091        ;; Loop until not BUSY
ENDIF
.L8098 RTS
;;
;; Initialise retries value
;; ------------------------
.L8099 LDA ABSWS+&0200  ;; Get default retries
       STA &CE          ;; Set current retries
       RTS
;;
;;
.L809F JMP L82C9
;;
;;
;; Access a drive using SCSI protocol
;; ==================================
;; Transfer up to &FF00 bytes at a time
;; XY=>control block:
;;   XY+ 0  Flag on entry, Returned result on exit
;;   XY+ 1  Addr0
;;   XY+ 2  Addr1
;;   XY+ 3  Addr2
;;   XY+ 4  Addr3
;;   XY+ 5  Command
;;   XY+ 6  Drive+Sector b16-19
;;   XY+ 7  Sector b8-b15
;;   XY+ 8  Sector b0-b7
;;   XY+ 9  Sector Count
;;   XY+10  -
;;   XY+11  Length0
;;   XY+12  Length1
;;   XY+13  Length2
;;   XY+14  Length3
;;   XY+15
;;
;; On exit: A=result. 0=OK, <>0=error, with ADFS error block filled in
;;
.L80A2 JSR L8328        ;; Wait for ensuring to complete
       STX &B0
       STY &B1          ;; &B0/1=>control block
       JSR LA6FD        ;; Check if directory loaded
       LDY #&05
       LDA (&B0),Y      ;; Get Command
       CMP #&2F         ;; Verify?
       BEQ L80DF        ;; Jump directly to do it
       CMP #&1B         ;; Park?
       BEQ L80DF        ;; Jump directly to do it
       JSR L8099        ;; Set number of retries
       BPL L80D7        ;; Jump into middle of retry loop
;;
;; This loop tries to access a drive. If the action returns 'Not ready' it
;; retries a number of times, allowing interuption by an Escape event.
;;
.L80BD JSR L80DF        ;; Do the specified command
       BEQ L8098        ;; Exit if ok
       CMP #&04         ;; Not ready?
       BNE L80D7        ;; Jump if result<>Not ready
;;                                         If Drive not ready, pause a bit
       LDY #&19         ;; Loop 25*256*256 times
.L80C8 BIT &FF          ;; Escape pressed?
       BMI L809F        ;; Abort with Escape error
       SEC
       SBC #&01
       BNE L80C8        ;; Loop 256 times with A
       DEX
       BNE L80C8        ;; Loop 256 times with X
       DEY
       BNE L80C8        ;; Loop 25 times with Y
;;
.L80D7 CMP #&40         ;; Result=Write protected?
       BEQ L80DF        ;; Abort immediately
       DEC &CE          ;; Dec number of retries
       BPL L80BD        ;; Jump to try again
;;                                         Drop through to try once more
;;
;; Try to access a drive
;; ---------------------
.L80DF LDY #&04
       LDA (&B0),Y      ;; Get Addr3
       TAX              ;; X=Addr3 - I/O or Language
       DEY
       LDA (&B0),Y      ;; Get Addr2 - Screen bank
       SHADOW_SELECT    ;; Set I/O and Screen settings
;;
;; No hard drive present, drive 0 to 7 map onto floppies 0 to 3.
;; When hard drives are present, drives 4 to 7 map onto floppies 0 to 3.
;;
IF INCLUDE_FLOPPY
       LDA &CD          ;; Get ADFS I/O status
       AND #&20         ;; Hard drive present?
       BNE L8111        ;; Jump when hard drive present
;;
;; Access a floppy drive
;; ---------------------
.L80F0 JSR LBA4B        ;; Do floppy operation
       BEQ L8110        ;; Completed ok
       PHA              ;; Save result
       LDY #&06         ;; Update ADFS error infomation
       LDA (&B0),Y      ;; Get Drive+Sector b16-b19
       ORA ABSWS+&0317  ;; OR with current drive
       STA ABSWS+&02D2  ;; Store
       INY
       LDA (&B0),Y      ;; Get Sector b8-b15
       STA ABSWS+&02D1
       INY
       LDA (&B0),Y      ;; Get Sector b0-b7
       STA ABSWS+&02D0
       PLA              ;; Restore result
       STA ABSWS+&02D3  ;; Store
.L8110 RTS
ENDIF
;;
;; ADFS Error Information:
;;   &C2D0 Sector b0-b7
;;   &C2D1 Sector b8-b15
;;   &C2D2 Sector b16-b19 and Drive
;;   &C2D3 SCSI error number
;;   &C2D4 Channel number if &C2D3.b7=1
;;
;;
;; Hard drive hardware is present. Check what drive is being accessed.
;;
.L8111 LDY #&06
       LDA (&B0),Y      ;; Get drive
       ORA ABSWS+&0317  ;; OR with current drive
IF INCLUDE_FLOPPY
       BMI L80F0        ;; Jump back with 4,5,6,7 as floppies
ENDIF
;;
;; Access a hard drive via the SCSI interface
;; ------------------------------------------
IF PATCH_IDE OR PATCH_SD
       LDY #0           ;; Access hard drive
       NOP
ELSE
       JSR L807E        ;; Write &01 to SCSI
ENDIF
;;                                         Put SCSI in command mode?
       INY              ;; Y=1
       LDA (&B0),Y      ;; Get Addr0
       STA &B2
       INY
       LDA (&B0),Y      ;; Get Addr1
       STA &B3          ;; &B2/3=address b0-b15
       INY
       LDA (&B0),Y      ;; Get Addr2
       CMP #&FE
       BCC L8134        ;; Addr<&FFFE0000, language space
       INY
       LDA (&B0),Y      ;; Get Addr3
       INC A
       BEQ L8137        ;; Address &FFxxxxxx, use I/O memory
.L8134 JSR L8020        ;; Claim Tube
.L8137
IF PATCH_SD

include "SD_Driver.asm"

ELIF PATCH_IDE
       LDY #5           ;; Get command, CC=Read, CS=Write
       LDA (&B0),Y
       CMP #&09
       AND #&FD         ;; Jump if Read (&08) or Write (&0A)
       EOR #&08
       BEQ CommandOk
       LDA #&27         ;; Return 'unsupported command' otherwise
       BRA CommandExit
.CommandOk
       LDY #9
.CommandSaveLp
       LDA &7F,Y        ;; Save &80-&89 and copy block
       PHA
       LDA (&B0),Y
       STA &7F,Y
       DEY
       BNE CommandSaveLp
       LDA &B0
       PHA
       LDA &B1
       PHA
       JSR UpdateDrive  ;; Merge drive
;;     LDA #&7F
       STA &B0          ;; Point to block in RAM
       STY &B1
       PHP              ;; Set shape to c*4*64
       JSR SetGeometry
       PLP
.CommandLoop
       LDX #2
.Twice                  ;; First pass to seek sector
       BIT &CD
       BVC CommandStart ;; Accessing I/O memory
       PHP
       PHX
       LDX #<(ABSWS+&0227) ;; Point to address block
       LDY #>(ABSWS+&0227)
       LDA #0           ;; Set Tube action
       ROL A
       EOR #1
       JSR L8213
       PLX
       PLP
.CommandStart           ;; C=R/W, &B0/1=>block
       JSR SetSector    ;; Set sector, count, command
.TransferLoop
       JSR WaitForData
       AND #&21
       BNE TransDone
       BIT &CD
       BVS TransTube
       BCC IORead
.IOWrite
       LDA (&80),Y
       STA &FC40
       BRA TransferByte
.IORead
       LDA &FC40
       STA (&80),Y
       BRA TransferByte
.TransTube
       BCC TubeRead
.TubeWrite
       LDA &FEE5
       STA &FC40
       BRA TransferByte
.TubeRead
       LDA &FC40
       STA &FEE5
       BRA TransferByte
.CommandDone
       JSR GetResult    ;; Get IDE result
.CommandExit
       PHA              ;; Release Tube
       JSR L803A
       PLA
       LDX &B0          ;; Restore registers, set EQ flag
       LDY &B1
       AND #&7F
       RTS
.TransferByte
       INY              ;; Loop for 256 bytes
       BNE TransferLoop
       DEX
       BNE Twice        ;; Second pass to do real transfer
       INC &81
       LDA &FC47
       AND #&21
       BNE TransDone    ;; Error occured
       INC ABSWS+&0228
       BNE TubeAddr     ;; Increment Tube address
       INC ABSWS+&0229
       BNE TubeAddr
       INC ABSWS+&022A
.TubeAddr
       INC &87          ;; Increment sector
       BNE TransCount
       INC &86
       BNE TransCount
       INC &85
.TransCount
       DEC &88          ;; Loop for all sectors
       BNE CommandLoop  ;; Done, check for errors
.TransDone
       PLA              ;; Restore pointer
       STA &B1
       PLA
       STA &B0
       INY
.CommandRestore         ;; Restore memory
       PLA
       STA &7F,Y
       INY
       CPY #10
       BNE CommandRestore
       BRA CommandDone  ;; Jump to get result

.SetGeometry
       JSR WaitNotBusy
       LDA #64          ;; 64 sectors per track
       STA &FC42
       STA &FC43
       LDY #6           ;; Get drive number
       LDA (&B0),Y
       LSR A
       LSR A
       ORA #3
       JSR SetDriveA
       LDA #&91
       BNE SetCmd       ;; 4 heads per cylinder
ELSE
       LDY #&05
       LDA (&B0),Y      ;; Get Command
       JSR L833E        ;; Send to SCSI data port
       INY
       LDA (&B0),Y      ;; Get Drive
       ORA ABSWS+&0317  ;; OR with current drive
       STA ABSWS+&0333
       JMP L814C        ;; Send rest of command block
;;
.L814A LDA (&B0),Y      ;; Get a command block byte
.L814C JSR L833E        ;; Send to SCSI data port
       JSR L8332        ;; Wait until SCSI busy
       BPL L8159        ;; If SCSI says enough command
       BVS L8159        ;; bytes sent, jump ahead
       INY              ;; Keep sending command block
       BNE L814A        ;; until SCSI says 'stop!'
.L8159 LDY #&05
       LDA (&B0),Y      ;; Get Command
       AND #&FD         ;; Lose bit 1
       EOR #&08         ;; Is Command &08 or &0A?
       BEQ L81DB        ;; Jump if not Read or Write
       JSR L8332        ;; Wait until SCSI busy
       CLC              ;; CC=Read
       BVC L816A        ;; Jump past with Read
       SEC              ;; CS=Write
.L816A LDY #&00         ;; Initialise Y to 0
       BIT &CD          ;; Accessing Tube?
       BVC L817C        ;; No, jump ahead to do the transfer
       LDX #<(ABSWS+&0227)
       LDY #>(ABSWS+&0227) ;; XY=>Tube address
       LDA #&00         ;; A=0
       PHP              ;; Save CC/CS state
       ROL A            ;; A=0/1 for Read/Write
       JSR L8213        ;; Claim the Tube
       PLP              ;; Restore CC/CS state
;;
;; Do a data transfer to/from SCSI device
;; --------------------------------------
.L817C JSR L8332        ;; Check SCSI status
       BMI L81AD        ;; Transfer finished
       BIT &CD          ;; Check Tube/Direction flags
       BVS L819B        ;; Jump for Tube transfer
       BCS L818E        ;; Jump for I/O read
;;
;;                                         I/O write
       LDA (&B2),Y      ;; Get byte from memory
       STA &FC40        ;; Write to SCSI data port
       BRA L8193        ;; Jump to update address
;;
.L818E LDA &FC40        ;; Read byte from SCSI data port
       STA (&B2),Y      ;; Store byte in memory
.L8193 INY              ;; Point to next byte
       BNE L817C        ;; Loop for 256 bytes
       INC &B3          ;; Increment address high byte
       JMP L817C        ;; Loop for next 256 bytes
;;
.L819B BCS L81A5        ;; Jump for Tube read
       LDA &FEE5        ;; Get byte from Tube
       STA &FC40        ;; Write byte to SCSI data port
       BRA L817C        ;; Loop for next byte
;;
.L81A5 LDA &FC40        ;; Get byte from SCSI data port
       STA &FEE5        ;; Write to Tube
       BRA L817C        ;; Loop for next byte
;;
.L81AD JSR L803A        ;; Release Tube and restore screen
.L81B0 JSR L8332        ;; Wait for SCSI data ready
       LDA &FC40        ;; Get result byte
       JSR L8332        ;; Wait for SCSI data ready
       TAY              ;; Save result
       JSR L806F        ;; Get SCSI status
       AND #&01
       BEQ L81B0        ;; Loop to try to get result again
       TYA              ;; Get result back
       LDX &FC40        ;; Get second result byte
       BEQ L81CA        ;; OK, jump to return result
       JMP L82A5        ;; Return result=&7F
;;
.L81CA TAX              ;; Save result in X
       AND #&02         ;; Check b1
       BEQ L81D2        ;; If b1=0, return with &00
       JMP L825D        ;; Get status from SCSI and return it
;;
.L81D2 LDA #&00         ;; A=0 - OK
.L81D4 LDX &B0          ;; Restore XY pointer
       LDY &B1
       AND #&7F         ;; Lose bit 7
       RTS              ;; Return with result in A
;;
;;
;; &CD ADFS status flag
;; --------------------
;; b7 Tube present
;; b6 Tube being used
;; b5 Hard Drive present
;; b4 FSM in memory inconsistant/being loaded
;; b3 -
;; b2 *OPT1 setting
;; b1 Bad Free Space Map
;; b0 Files being ensured
;;
;;
;; Not Read or Write
;; -----------------
.L81DB LDY #&00
       BIT &CD
       BVS L821F
.L81E1 JSR L8332
       BMI L81AD
       BVS L81F4
.L81E8 LDA (&B2),Y
       STA &FC40
       INY
       BNE L81E8
       INC &B3
       BRA L81E1
;;
.L81F4 LDA &FC40
       STA (&B2),Y
       INY
       BNE L81F4
       INC &B3
       BRA L81E1
;;
.L8200 INC ABSWS+&0228
       BNE L820D
       INC ABSWS+&0229
       BNE L820D
       INC ABSWS+&022A
.L820D LDX #<(ABSWS+&0227)
       LDY #>(ABSWS+&0227)
       RTS
ENDIF
;;
.L8212 SEI
.L8213 JSR &0406
       LDY #&00
       JSR L821B
.L821B JSR L821E
.L821E RTS
;;
IF PATCH_SD
ELIF PATCH_IDE
.SetSector
       PHP
       JSR WaitNotBusy  ;; Save CC/CS Read/Write
       LDY #8
       LDA #1           ;; One sector
       STA &FC42
       CLC              ;; Set sector b0-b5
       LDA (&B0),Y
       AND #63
       ADC #1
       STA &FC43
       DEY              ;; Set sector b8-b15
       LDA (&B0),Y
       STA &FC44
       DEY              ;; Set sector b16-b21
       LDA (&B0),Y
       JSR SetCylinder
       INY              ;; Merge Drive and Head
       INY
       EOR (&B0),Y
       AND #2
       EOR (&B0),Y
       JSR SetDrive     ;; Get command &08 or &0A
       DEY
       DEY
       DEY
       LDA (&B0),Y
.SetCommand
       AND #2           ;; Copy ~b1 into Cy
       PHA
       EOR #2
       LSR A
       LSR A
       PLA              ;; Translate CS->&20 or CC->&30
       ASL A
       ASL A
       ASL A
       ORA #&20
       LDY #0           ;; Set command &08 or &0A
       PLP
.SetCmd
       STA &FC47
       RTS
.SetDrive
       ROL A            ;; Move into position
       ROL A
       ROL A
.SetDriveA
       AND #&13         ;; Set device + sector b6-b7
       STA &FC46
       RTS
.SetCylinder
       PHA              ;; Set sector b16-b21
       AND #&3F
       STA &FC45
       PLA              ;; Get Drive 0-1/2-3 into b1
       ROL A
       ROL A
       ROL A
       ROL A
       RTS
.SetRandom
       JSR SetCylinder  ;; Set sector b16-b21
       EOR ABSWS+&0201,X ;; Merge Drive and Head
       AND #&02
       EOR ABSWS+&0201,X
       JSR SetDrive     ;; Set device and command
       PLA
       PHP
       BRA SetCommand
.GetResult
       LDA &FC47        ;; Get IDE result
       AND #&21
       BEQ GetResOk
       LDA &FC41        ;; Get IDE error code, CS already set
       LDX #&FF
.GetResLp
       INX              ;; Translate result code
       ROR A
       BCC GetResLp
       LDA ResultCodes,X
.GetResOk
       RTS
       BNE &82A5      ;; Junk - so a binary compare will pass
       TXA            ;; Junk - so a binary compare will pass
       JMP &81D4      ;; Junk - so a binary compare will pass
       LDA #&FF       ;; Junk - so a binary compare will pass
       JMP &81D4      ;; Junk - so a binary compare will pass
ELSE
.L821F LDX #&27
       LDY #&C2
.L8223 JSR L8332
       BPL L822B
       JMP L81AD
;;
.L822B BVS L8245
       PHP
       LDA #&06
       JSR L8212
.L8233 NOP
       NOP
       NOP
       LDA &FEE5
       STA &FC40
       INY
       BNE L8233
       JSR L8200
       PLP
       BRA L8223
;;
.L8245 PHP
       LDA #&07
       JSR L8212
.L824B NOP
       NOP
       NOP
       LDA &FC40
       STA &FEE5
       INY
       BNE L824B
       JSR L8200
       PLP
       BRA L8223
;;
;;
;; Read result from SCSI and return it as a result
;; -----------------------------------------------
.L825D JSR L807E        ;; Set SCSI to command mode
       LDA #&03
       TAX
       TAY
       JSR L833E        ;; Send &03 to SCSI
       LDA ABSWS+&0333
       AND #&E0
       JSR L833E        ;; Send drive to SCSI
.L826F JSR L833E        ;; Send &00 to SCSI
       DEY
       BPL L826F        ;; Send 4 zeros: sends &03 dd &00 &00 &00 &00
.L8275 JSR L8332        ;; Wait for SCSI
       LDA &FC40        ;; Get byte from SCSI
       STA ABSWS+&02D0,X ;; Store in error block
       DEX
       BPL L8275        ;; Loop to fetch four bytes, err, sec.hi, sec.mid, sec.lo
       LDA ABSWS+&0333
       AND #&E0
       ORA ABSWS+&02D2  ;; ORA drive number with current drive
       STA ABSWS+&02D2
       JSR L8332        ;; Wait for SCSI
       LDX ABSWS+&02D3  ;; Get returned error number
       LDA &FC40        ;; Get a byte from SCSI
       JSR L8332        ;; Wait for SCSI
       LDY &FC40        ;; Get another byte from SCSI
       BNE L82A5        ;; Second byte is non-zero, jump to return &7F
       AND #&02         ;; Test bit 1 of first byte
       BNE L82A5        ;; If set, jump to return &7F
       TXA
       JMP L81D4        ;; Return returned SCSI result
;;
.L82A5 LDA #&FF         ;; Result=&FF
       JMP L81D4        ;; Jump to return result
ENDIF
;;
;; Do predefined SCSI operations
;; -----------------------------
.L82AA LDX #<(ABSWS+&0215) ;; Point to &C215
       LDY #>(ABSWS+&0215)
.L82AE JSR L80A2        ;; Do a disk operation
       BNE L82BD        ;; Jump ahead with error
       RTS              ;; Exit if OK
;;
;; Do a disk access
;; ----------------
.L82B4 LDA ABSWS+&022F
       STA ABSWS+&0317
       JMP L8BE2        ;; Not Found error
;;
.L82BD CMP #&25         ;; Hard drive error &25 (Bad drive)?
       BEQ L82B4        ;; Jump to give 'Not found' error
       CMP #&65         ;; Floppy error &25 (Bad drive)
       BEQ L82B4        ;; Jump to give 'Not found' error
       CMP #&6F         ;; Floppy error &2F (Abort)?
       BNE L82DC        ;; If no, report a disk error
;;
.L82C9 JSR L849A
.L82CC LDA #&7E
       JSR &FFF4        ;; Acknowledge Escape state
       JSR L836B        ;; Generate an error
       EQUB &11         ;; ERR=17
       EQUS "Escape"    ;; REPORT="Escape"
       EQUB &00
;;
.L82DC CMP #&04         ;; Hard drive error &04 (Not ready)?
       BNE L82F4        ;; No, try other errors
       JSR L836B        ;; Generate an error "Drive not ready"
       EQUB &CD         ;; ERR=205
       EQUS "Drive not ready"
       EQUB &00
;;
.L82F4 CMP #&40         ;; Floppy drive error &10 (WRPROT)?
       BEQ L830B        ;; Jump to report "Disk protected"
                        ;; All other results, give generic
                        ;; error message
       JSR L89D8
       TAX
       JSR L8374
       EQUB &C7         ;; ERR=199
       EQUS "Disc error"
       EQUB &00
;;
.L830B JSR L834E        ;; Generate an error
       EQUB &C9         ;; ERR=201
       EQUS "Disc protected"
       EQUB &00
;;
IF NOT(PATCH_SD)        ;; Called only from Floppy and IDE code, not SD code
.L831E JSR L8324
       BNE L82BD        ;; Generate disk error
       RTS
;;
.L8324 JSR L833E        ;; Wait until nor busy, then write command to command register
       RTS
ENDIF
;;
;;
;; Wait until any ensuring completed
;; =================================
IF PATCH_SD
.L8328 LDA &CD
       AND #&FE
       STA &CD
       RTS
ELIF PATCH_IDE
.L8328 LDA &CD
       AND #&FE
       STA &CD
       RTS
       BNE L8328        ;; Junk - so a binary compare will pass
       RTS              ;; Junk - so a binary compare will pass
ELSE
.L8328 LDA #&01         ;; Looking at bit 0
       PHP              ;; Save IRQ disable
       CLI              ;; Enable IRQs for a moment
       PLP              ;; Restore IRQ disable
       BIT &CD          ;; Check Ensure
       BNE L8328        ;; Loop back if set
       RTS
ENDIF
;;
;; Wait until SCSI ready to respond
;; --------------------------------
IF PATCH_SD
.L8332  RTS
ELIF PATCH_IDE
.WaitNotBusy
.L8332  PHP             ;; Get IDE status
.L8333  JSR L806F
        AND #&C0        ;; Wait for IDE not busy and ready
        CMP #&40
        BNE L8333
        PLP
        RTS
ELSE
.L8332 PHA              ;; Save A
.L8333 JSR L806F        ;; Get SCSI status
       AND #&20         ;; BUSY?
       BEQ L8333        ;; Loop until BUSY
       PLA              ;; Restore A
       BIT &CC
       RTS
ENDIF
;;
IF NOT(PATCH_SD)        ;; Called only from Floppy and IDE code, not SD code
.L833E JSR L8332        ;; Wait until SCSI OR IDE ready
       BVS L8349
       STA &FC40        ;; This works because the SCSI command register is shared
       LDA #&00
       RTS
;;
.L8349 PLA
       PLA
       JMP L81AD
ENDIF
;;
.L834E LDX ABSWS+&022F
       INX
       BNE L836B
       LDX ABSWS+&022E
       INX
       BNE L8365
       LDY #&02
.L835C LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L835C
.L8365 LDA ABSWS+&0317
       STA ABSWS+&022F
.L836B JSR L89D8
       LDA #&10
       TRB &CD
.L8372 LDX #&00
;;
.L8374 PLA
       STA &B2
       PLA
       STA &B3
       LDA #&10
       TRB &CD
       LDY #&00
.L8380 INY
       LDA (&B2),Y
       STA &0100,Y
       BNE L8380
       TXA
       BEQ L83DA
       LDA #&20
       STA &0100,Y
       TXA
       CMP #&30
       BCS L839B
.L8395 JSR L8451
       JMP L83A2
;;
.L839B CMP #&3A
       BCS L8395
       JSR L846D
.L83A2 LDX #&04
.L83A4 INY
       LDA L8440,X
       STA &0100,Y
       DEX
       BPL L83A4
       LDA ABSWS+&02D2
       ASL A
       ROL A
       ROL A
       ROL A
       JSR L8462
       INY
       STA &0100,Y
       LDA #&2F
       INY
       STA &0100,Y
       LDA ABSWS+&02D2
       AND #&1F
       LDX #&02
       BNE L83CE
.L83CB LDA ABSWS+&02D0,X
.L83CE JSR L8451
       DEX
       BPL L83CB
       INY
       LDA #&00
       STA &0100,Y
.L83DA LDA ABSWS+&02D5
       BEQ L840F
       LDX #&0B
       DEY
.L83E2 LDA L8445,X
       INY
       STA &0100,Y
       DEX
       BPL L83E2
       LDA ABSWS+&02D5
       JSR L846D
       PHY
       LDA #&C6
       STA ABSWS+&02D9
       JSR L84C4
       CPX ABSWS+&02D5
       PHP
       LDX #&BD
       PLP
       BEQ L840B
       CPY ABSWS+&02D5
       BNE L840E
       LDX #&C0
.L840B JSR L84D3
.L840E PLY
.L840F LDA ABSWS+&02CE
       BNE L8417
       JSR LA7D4
.L8417 LDA #&00
       STA &0100
       STA &0101,Y
       JSR L803A
       LDA &0101
       CMP #&C7
       BNE L843D
       DEC A
       JSR L84C4
       PHY
       TXA
       LDX #<L84BD
       JSR L84CB
       PLA
       LDX #<L84C0
       JSR L84CB
       JSR L849A
.L843D JMP &0100
;;
.L8440 EQUS ": ta "
.L8445 EQUS " lennahc no "
.L8451 PHA
       LSR A
       LSR A
       LSR A
       LSR A
       JSR L845A
       PLA
.L845A JSR L8462
       INY
       STA &0100,Y
       RTS
;;
.L8462 AND #&0F
       ORA #&30
       CMP #&3A
       BCC L846C
       ADC #&06
.L846C RTS
;;
.L846D BIT L8483
       LDX #&64
       JSR L847D
       LDX #&0A
       JSR L847D
       CLV
       LDX #&01
.L847D PHP
       STX &B3
       LDX #&2F
       SEC
.L8483 INX
       SBC &B3
       BCS L8483
       ADC &B3
       PLP
       PHA
       TXA
       BVC L8494
       CMP #&30
       BEQ L8498
       CLV
.L8494 INY
       STA &0100,Y
.L8498 PLA
       RTS
;;
.L849A LDX #&0C
       LDA #&FF
.L849E STA ABSWS+&022B,X
       STA ABSWS+&0313,X
       DEX
       BNE L849E
       JSR LA189
       JSR LA189
       LDY #&00
       TYA
.L84B0 STA ABSWS+&0100,Y
       STA ABSWS+&0000,Y
       STA ABSWS+&0400,Y
       INY
       BNE L84B0
.L84BC RTS
;;
.L84BD EQUS "E."        ;; Abbreviation of 'Exec'
       EQUB &0D
;;
.L84C0 EQUS "SP."       ;; Abbreviation of 'Spool'
       EQUB &0D
;;
;; OSBYTE READ
;; -----------
.L84C4 LDY #&FF
.L84C6 LDX #&00
       JMP &FFF4        ;; Osbyte A,&00,&FF
;;
;; Close Spool or Exec if ADFS channel
;; -----------------------------------
.L84CB CMP #&30         ;; Check against lowest ADFS handle
       BCC L84BC        ;; Exit if not ADFS
       CMP #&3A         ;; Check against highest ADFS handle
       BCS L84BC        ;; Exit if not ADFS
.L84D3 LDY #>L84BD      ;; Point to *Spool or *Exec
       JMP &FFF7        ;; Jump to close via MOS
;;
.L84D8 EQUS &0D, "SEY"
.L84DC EQUS &00, "Hugo"
;;
.L84E1 LDA ABSWS+&0237
       ORA ABSWS+&0238
       ORA ABSWS+&0239
       BNE L84ED
       RTS
;;
.L84ED LDX #&00
.L84EF CPX ABSWS+&01FE
       BCS L8526
       INX
       INX
       INX
       STX &B2
       LDY #&02
.L84FB DEX
       LDA ABSWS+&0000,X
       CMP ABSWS+&0234,Y
       BCS L8508
       LDX &B2
       BRA L84EF
;;
.L8508 BNE L850D
       DEY
       BPL L84FB
.L850D LDX &B2
       DEX
       DEX
       DEX
       STX &B2
       CLC
       PHP
       LDY #&00
.L8518 PLP
       LDA ABSWS+&0234,Y
       ADC ABSWS+&0237,Y
       PHP
       CMP ABSWS+&0000,X
       BEQ L8529
       PLP
.L8526 JMP L85B3
;;
.L8529 INX
       INY
       CPY #&03
       BNE L8518
       PLP
       LDX &B2
       BEQ L8596
       CLC
       PHP
       LDY #&00
.L8538 PLP
       LDA ABSWS-3,X
       ADC ABSWS+&00FD,X
       PHP
       CMP ABSWS+&0234,Y
       BEQ L854A
       LDX &B2
       PLA
       BRA L8596
;;
.L854A INX
       INY
       CPY #&03
       BNE L8538
       PLP
       LDX &B2
       LDY #&00
       CLC
       PHP
.L8557 PLP
       LDA ABSWS+&00FD,X
       ADC ABSWS+&0237,Y
       STA ABSWS+&00FD,X
       PHP
       INX
       INY
       CPY #&03
       BNE L8557
       PLP
       LDY #&02
       LDX &B2
       CLC
.L856E LDA ABSWS+&00FD,X
       ADC ABSWS+&0100,X
       STA ABSWS+&00FD,X
       INX
       DEY
       BPL L856E
.L857B CPX ABSWS+&01FE
       BCS L858F
       LDA ABSWS+&0100,X
       STA ABSWS+&00FD,X
       LDA ABSWS+&0000,X
       STA ABSWS-3,X
       INX
       BNE L857B
.L858F DEX
       DEX
       DEX
       STX ABSWS+&01FE
       RTS
;;
.L8596 LDY #&00
       CLC
       PHP
.L859A LDA ABSWS+&0234,Y
       STA ABSWS+&0000,X
       PLP
       LDA ABSWS+&0100,X
       ADC ABSWS+&0237,Y
       STA ABSWS+&0100,X
       PHP
       INY
       INX
       CPY #&03
       BNE L859A
       PLP
       RTS
;;
.L85B3 LDX &B2
       BEQ L85EB
       CLC
       PHP
       LDY #&00
.L85BB PLP
       LDA ABSWS-3,X
       ADC ABSWS+&00FD,X
       PHP
       CMP ABSWS+&0234,Y
       BEQ L85CB
       PLP
       BRA L85EB
;;
.L85CB INX
       INY
       CPY #&03
       BNE L85BB
       PLP
       LDY #&00
       LDX &B2
       CLC
       PHP
.L85D8 PLP
       LDA ABSWS+&00FD,X
       ADC ABSWS+&0237,Y
       STA ABSWS+&00FD,X
       PHP
       INX
       INY
       CPY #&03
       BNE L85D8
       PLP
       RTS
;;
.L85EB LDA ABSWS+&01FE
       CMP #&F6
       BCC L85FF
       JSR L834E
       EQUB &99         ;; ERR=153
       EQUS "Map full"
       EQUB &00
;;
.L85FF LDX ABSWS+&01FE
.L8602 CPX &B2
       BEQ L8615
       DEX
       LDA ABSWS+&0000,X
       STA ABSWS+&0003,X
       LDA ABSWS+&0100,X
       STA ABSWS+&0103,X
       BRA L8602
;;
.L8615 LDY #&00
.L8617 LDA ABSWS+&0234,Y
       STA ABSWS+&0000,X
       LDA ABSWS+&0237,Y
       STA ABSWS+&0100,X
       INX
       INY
       CPY #&03
       BNE L8617
       LDA ABSWS+&01FE
       ADC #&02
       STA ABSWS+&01FE
.L8631 RTS
;;
.L8632 LDX #&00
       STX ABSWS+&025D
       STX ABSWS+&025E
       STX ABSWS+&025F
.L863D CPX ABSWS+&01FE
       BEQ L8631
       LDY #&00
       CLC
       PHP
.L8646 PLP
       LDA ABSWS+&0100,X
       ADC ABSWS+&025D,Y
       STA ABSWS+&025D,Y
       PHP
       INY
       INX
       CPY #&03
       BNE L8646
       PLP
       JMP L863D
;;
.L865B LDX #&FF
       STX &B3
       INX
.L8660 CPX ABSWS+&01FE
       BCC L86E1
       LDX &B3
       CPX #&FF
       BNE L86A5
       JSR L8632
       LDY #&00
       LDX #&02
       SEC
.L8673 LDA ABSWS+&025D,Y
       SBC ABSWS+&023D,Y
       INY
       DEX
       BPL L8673
       BCS L868D
.L867F JSR L834E
       EQUB &C6         ;; ERR=198
       EQUS "Disc full"
       EQUB &00
;;
.L868D JSR L834E
       EQUB &98         ;; ERR=152
       EQUS "Compaction required"
       EQUB &00
;;
.L86A5 LDY #&02
.L86A7 DEX
       LDA ABSWS+&0000,X
       STA ABSWS+&023A,Y
       DEY
       BPL L86A7
       INY
       LDX &B3
       CLC
       PHP
.L86B6 PLP
       LDA ABSWS-3,X
       ADC ABSWS+&023D,Y
       STA ABSWS-3,X
       PHP
       INX
       INY
       CPY #&03
       BNE L86B6
       PLP
       LDY #&00
       LDX &B3
       SEC
       PHP
.L86CE PLP
       LDA ABSWS+&00FD,X
       SBC ABSWS+&023D,Y
       STA ABSWS+&00FD,X
       PHP
       INX
       INY
       CPY #&03
       BNE L86CE
       PLP
       RTS
;;
.L86E1 LDY #&02
       INX
       INX
       INX
       STX &B2
.L86E8 DEX
       LDA ABSWS+&0100,X
       CMP ABSWS+&023D,Y
       BCC L872C
       BNE L8723
       DEY
       BPL L86E8
       LDX &B2
       LDY #&02
.L86FA DEX
       LDA ABSWS+&0000,X
       STA ABSWS+&023A,Y
       DEY
       BPL L86FA
       LDX &B2
.L8706 CPX ABSWS+&01FE
       BCS L871A
       LDA ABSWS+&0000,X
       STA ABSWS-3,X
       LDA ABSWS+&0100,X
       STA ABSWS+&00FD,X
       INX
       BNE L8706
.L871A LDA ABSWS+&01FE
       SBC #&03
       STA ABSWS+&01FE
       RTS
;;
.L8723 LDX &B3
       INX
       BNE L872C
       LDA &B2
       STA &B3
.L872C LDX &B2
       JMP L8660
;;
.L8731 INC &B4
       BNE L8737
       INC &B5
.L8737 RTS
;;
.L8738 JSR LA50D
       JSR L8D79
       LDY #&00
       STY ABSWS+&02C0
.L8743 LDA (&B4),Y
       AND #&7F
       CMP #&2E
       BEQ L8753
       CMP #&22
       BEQ L8753
       CMP #&20
       BCS L8755
.L8753 LDX #&00
.L8755 RTS
;;
.L8756 LDY #&0A
.L8758 JSR L8743
       BEQ L876D
       DEY
       BPL L8758
;;
.L8760 JSR L836B
       EQUB &CC         ;; ERR=204
       EQUS "Bad name"
       EQUB &00
;;
.L876D LDY #&09
.L876F LDA (&B6),Y
       AND #&7F
       STA ABSWS+&0262,Y
       DEY
       BPL L876F
       INY
       LDX #&00
.L877C CPX #&0A
       BCS L87C1
       LDA ABSWS+&0262,X
       CMP #&21
       BCC L87C1
       ORA #&20
       STA ABSWS+&022B
       CPY #&0A
       BCS L87AB
       JSR L8743
       BEQ L87B0
       CMP #&2A
       BEQ L87D1
       CMP #&23
       BEQ L87A6
       ORA #&20
       CMP ABSWS+&022B
       BCC L87B0
       BNE L87AA
.L87A6 INX
       INY
       BNE L877C
.L87AA RTS
;;
.L87AB JSR L8743
       BNE L8760
.L87B0 JSR L8743
       CMP #&23
       BEQ L87CE
       CMP #&2A
       BEQ L87CE
       DEY
       BPL L87B0
       CMP #&FF
       RTS
;;
.L87C1 CPY #&0A
       BEQ L87AA
       JSR L8743
       BEQ L87AA
       CMP #&2A
       BEQ L87D1
.L87CE CMP #&00
       RTS
;;
.L87D1 INY
.L87D2 LDA ABSWS+&0262,X
       AND #&7F
       CMP #&21
       BCC L87F4
       CPX #&0A
       BCS L87F4
       PHX
       PHY
       JSR L877C
       BEQ L87EE
       PLY
       PLX
       INX
       BNE L87D2
.L87EB CPX #&00
       RTS
;;
.L87EE PLA
       PLA
.L87F0 LDA #&00
       SEC
       RTS
;;
.L87F4 CPY #&0A
       BCS L87F0
       LDA (&B4),Y
       CMP #&21
       BCC L87F0
       CMP #&2E
       BEQ L87F0
       CMP #&22
       BEQ L87F0
       CMP #&2A
       BEQ L87D1
       BNE L87EB
.L880C JSR LA50D
       JSR L93CC
       JSR LA714
.L8815 LDY #&00
       LDA (&B6),Y
       BEQ L882E
       JSR L8756
       BEQ L8830
       BCC L8830
       LDA &B6
       ADC #&19
       STA &B6
       BCC L8815
       INC &B7
       BNE L8815
.L882E CMP #&0F
.L8830 RTS
;;
;; Control block to load FSM
.L8831 EQUB &01
       EQUB <ABSWS
       EQUB >ABSWS
       EQUB &FF
       EQUB &FF
       EQUB &08
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &02
.L883B EQUB &00
;;
;; Control block to load '$'
.L883C EQUB &01
       EQUB <(ABSWS+&0400)
       EQUB >(ABSWS+&0400)
       EQUB &FF
       EQUB &FF
       EQUB &08
       EQUB &00
       EQUB &00
       EQUB &02
       EQUB &05
       EQUB &00
;;
;; Check drive character
.L8847 CMP #&30
       BCC L886D        ;; <'0' - error
       CMP #&38
       BCC L885A        ;; '0'-'7' - Ok
       ORA #&20         ;; For to lower case
       CMP #&61         ;; <'A' - error
       BCC L886D
       CMP #&69
       BCS L886D        ;; >'H' - error
       DEC A            ;; Convert 'A'-'H' to '0' to '7'
.L885A PHA
IF INCLUDE_FLOPPY
       LDA &CD
       AND #&20         ;; Hard drive present?
       BNE L8865
       PLA              ;; No hard drive, reduce drive
       AND #&03         ;; number to 0-3
       PHA
ENDIF
.L8865 PLA
       AND #&07         ;; Drop top bits to get 0-7 (or 0-3)
       LSR A            ;; Move to top three bits
       ROR A
       ROR A
       ROR A
       RTS
;;
.L886D JMP L8760
;;
.L8870 JSR L8738
       BEQ L886D
.L8875 JSR L8738
       BEQ L8899
       CMP #&3A
       BNE L88EF
       JSR L8731
       LDX ABSWS+&022F
       INX
       BNE L888D
       LDA ABSWS+&0317
       STA ABSWS+&022F
.L888D JSR L8743
       JSR L8847
       STA ABSWS+&0317
.L8896 JSR L8731
.L8899 LDX ABSWS+&0317
       INX
       BNE L88AD
IF INCLUDE_FLOPPY
       LDA &CD          ;; Get ADFS status byte
       AND #&20         ;; Hard drive present?
       BEQ L88AA        ;; Jump if no hard drive
ENDIF
       LDA ABSWS+&02D8        ;; Get CMOS byte RAM copy
       AND #&80         ;; Get hard drive flag
.L88AA STA ABSWS+&0317        ;; Store in current drive
.L88AD LDA #&10
       TSB &CD          ;; Flag FSM inconsistant
       LDX #<L8831
       LDY #>L8831
       JSR L82AE        ;; Load FSM
       LDA #&10
       TRB &CD          ;; Flag FSM loaded
       LDA ABSWS+&022E
       BPL L88CC
       LDY #&02
.L88C3 LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L88C3
.L88CC LDY #>L883C
       LDX #<L883C
       JSR L82AE        ;; Load '$'
       LDA #&02
       STA ABSWS+&0314        ;; Set CURR to &000002 - '$'
       LDA #&00
       STA ABSWS+&0315
       STA ABSWS+&0316
       JSR LB4B9
       LDY #&00
       JSR L8743
       CMP #&2E
       BNE L8910
       JSR L8731
.L88EF LDY #&00
       JSR L8743
       AND #&FD
       CMP #&24
       BEQ L8896
       JSR LB546
.L88FD JSR L9456
       BNE L892A
       INY
       STY ABSWS+&02A2
       JSR L8743
       CMP #&2E
       BNE L892F
       JMP L8997
;;
.L8910 LDA #&24
       STA ABSWS+&0262
       LDA #&0D
       STA ABSWS+&0263
       LDA #<L94D3
       STA &B6
       LDA #>L94D3
       STA &B7
       LDA #&02
       STA ABSWS+&02C0
       LDA #&00
       RTS
;;
.L892A JSR L880C
       BEQ L893F
.L892F RTS
;;
.L8930 LDX #&01
       LDY #&03
       LDA (&B6),Y
       BPL L8939
       INX
.L8939 STX ABSWS+&02C0
       LDA #&00
       RTS
;;
.L893F LDY #&00
.L8941 JSR L8743
       CMP #&21
       BCC L8930
       CMP #&22
       BEQ L8930
       CMP #&2E
       BEQ L8953
       INY
       BNE L8941
.L8953 STY ABSWS+&02A2
.L8956 LDY #&03
       LDA (&B6),Y
       BMI L897B
       JSR L8964
       BEQ L8956
.L8961 LDA #&FF
       RTS
;;
.L8964 CLC
       LDA &B6
       ADC #&1A
       STA &B6
       BCC L896F
       INC &B7
.L896F LDY #&00
       LDA (&B6),Y
       BEQ L8961
       JSR L8756
       BNE L8964
       RTS
;;
.L897B LDY #&09
       LDA (&B6),Y
       BPL L8997
       AND #&7F
       STA (&B6),Y
       JSR L8F91
.L8988 JSR L836B
       EQUB &B0         ;; ERR=176
       EQUS "Bad rename"
       EQUB &00
;;
.L8997 LDA ABSWS+&02A2
       SEC
       ADC &B4
       STA &B4
       BCC L89A3
       INC &B5
.L89A3 LDA ABSWS+&022E
       INC A
       BNE L89B4
       LDY #&02
.L89AB LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L89AB
.L89B4 LDX #&0A
.L89B6 LDA L883C,X
       STA ABSWS+&0215,X
       DEX
       BPL L89B6
       LDX #&02
       LDY #&16
.L89C3 LDA (&B6),Y
       STA ABSWS+&021B,X
       STA ABSWS+&02FE,Y
       INY
       DEX
       BPL L89C3
       JSR L82AA
       JMP L88FD
;;
.L89D5 LDA ABSWS+&02C0
;;
.L89D8 PHA
       LDA ABSWS+&022F
       CMP #&FF
       BEQ L89EF
       STA ABSWS+&0317
       LDA #&FF
       STA ABSWS+&022F
       LDX #<L8831
       LDY #>L8831
       JSR L82AE        ;; Load FSM
.L89EF LDA ABSWS+&022E
       CMP #&FF
       BEQ L8A22
       TAX
       LDY #&0A
.L89F9 LDA L883C,Y      ;; Copy parameter block to
       STA ABSWS+&0215,Y      ;; load '$'
       DEY
       BPL L89F9
       STX ABSWS+&0316        ;; Copy parameters to &C215
       STX ABSWS+&021B
       LDA ABSWS+&022D
       STA ABSWS+&0315
       STA ABSWS+&021C
       LDA ABSWS+&022C
       STA ABSWS+&0314
       STA ABSWS+&021D
       LDA #&FF
       STA ABSWS+&022E
       JSR L82AA        ;; Do disk op from &C215
.L8A22 LDA &CD
       STA ABSWS+&0320
       JSR LA744        ;; Get WS address in &BA
       LDY #&FB
.L8A2C LDA ABSWS+&0300,Y      ;; Copy workspace to private
       STA (&BA),Y
       DEY
       BNE L8A2C
       LDA ABSWS+&0300
       STA (&BA),Y
       JSR LA761        ;; Reset workspace checksum
       LDX &B8
       LDY &B9
       PLA
.L8A41 RTS
;;
.L8A42 JSR L8A4A        ;; Do disk access
       BEQ L8A41        ;; No error, exit
       JMP L82BD        ;; Generate disk error
;;
;;
;; User Disk Access
;; ================
;; Do a disk access using SCSI protocol. Control block at &C215-&C224
;;
;;    Addr Ctrl
;;   &C215  Returned result
;;   &C216  Addr0
;;   &C217  Addr1
;;   &C218  Addr2
;;   &C219  Addr3
;;   &C21A  Command
;;   &C21B  Drive+Sector b16-b20
;;   &C21C  Sector b8-b15
;;   &C21D  Sector b0-b7
;;   &C21E  Sector Count
;;   &C21F  -
;;   &C220  Length0
;;   &C221  Length1
;;   &C222  Length2
;;   &C223  Length3
;;   &C224
;;
.L8A4A LDA ABSWS+&021A  ;; Get command
       CMP #&08         ;; Read?
       BEQ L8A68        ;; Jump forward with Read
       LDA ABSWS+&0220  ;; If Length0=0?
       BEQ L8A68        ;; Whole number of sectors
;;
;; Adjust the Length to be a whole number of sectors for writing
;;
       LDA #&0
       STA ABSWS+&0220
       INC ABSWS+&0221
       BNE L8A68
       INC ABSWS+&0222
       BNE L8A68
       INC ABSWS+&0223
;;
;; Length is now a whole number of sectors, a whole multiple of 256 bytes
;;
.L8A68 LDX #<(ABSWS+&0215)
       LDY #>(ABSWS+&0215) ;; XY=>control block
       LDA #&FF
       STA ABSWS+&021E     ;; Set initial sector count to &FF
;;
;; Transfer batches of &FF00 bytes until less than 64k left
;; --------------------------------------------------------
.L8A71 LDA ABSWS+&0223
       ORA ABSWS+&0222  ;; Get Length2+Length3
       BEQ L8ABC        ;; Jump if remaining length<64k
;;
       JSR L80A2        ;; Do a transfer
       BNE L8ACE        ;; Exit with any error
       LDA #&FF         ;; Update address
       CLC              ;; Addr=Addr+&0000FF00
       ADC ABSWS+&0217  ;; Addr1=Addr1+&FF
       STA ABSWS+&0217
       BCC L8A91        ;; No overflow
       INC ABSWS+&0218  ;; Addr2=Addr2+1
       BNE L8A91        ;; No overflow
       INC ABSWS+&0219  ;; Addr3=Addr3+1
;;
.L8A91 LDA #&FF         ;; Update sector
       CLC
       ADC ABSWS+&021D  ;; Sector=Sector+&FF
       STA ABSWS+&021D  ;; Sector0=Sector0+&FF
       BCC L8AA4        ;; No overflow
       INC ABSWS+&021C  ;; Sector1=Sector1+1
       BNE L8AA4        ;; No overflow
       INC ABSWS+&021B  ;; Sector2=Sector2+1
;;
.L8AA4 LDA ABSWS+&0221  ;; Update length
       SEC
       SBC #&FF         ;; Length=Length-&0000FF00
       STA ABSWS+&0221  ;; Length1=Length1-&FF
       BCS L8A71        ;; No overflow
       LDA ABSWS+&0222  ;; Get Length2
       BNE L8AB7        ;; No need to decrement
       DEC ABSWS+&0223  ;; Length3=Length3-1
.L8AB7 DEC ABSWS+&0222  ;; Length2=Length2-1
       BRA L8A71        ;; Loop back for another &FF00 bytes
;;
;; There is now less than 64k to transfer
;; --------------------------------------
.L8ABC LDA ABSWS+&0221  ;; Get Length1
       BEQ L8AC9        ;; Now less than 256 bytes to go
       STA ABSWS+&021E  ;; Set Sector Count
       JSR L80A2        ;; Do this transfer
       BNE L8ACE        ;; Exit with any error
;;
.L8AC9 LDA ABSWS+&0220  ;; Get Length0
       BNE L8ACF        ;; Jump to deal with any leftover bytes
.L8ACE RTS
;;
;; There are now less than 256 bytes left, must be reading
;; -------------------------------------------------------
.L8ACF STA ABSWS+&021E  ;; Store Length0 in Sector Count
       LDA ABSWS+&0221  ;; Get last length transfered
       CLC
       ADC ABSWS+&021D  ;; Add to Sector0
       STA ABSWS+&021D  ;; Store in Sector0
       BCC L8AE6
       INC ABSWS+&021C  ;; Increment Sector1
       BNE L8AE6
       INC ABSWS+&021B  ;; Increment Sector2
.L8AE6 LDA ABSWS+&0221  ;; Get Length1
       CLC
       ADC ABSWS+&0217  ;; Add to Addr1
       STA ABSWS+&0217  ;; Store Addr1
       BCC L8AFA
       INC ABSWS+&0218  ;; Increment Addr2
       BNE L8AFA
       INC ABSWS+&0219  ;; Increment Addr3
.L8AFA JSR L8328        ;; Wait for ensuring to finish
       JSR L8099        ;; Initialise retries
.L8B00 JSR L8B09        ;; Call to load data
       BEQ L8ACE        ;; All ok, so exit
       DEC &CE          ;; Decrement retries
       BPL L8B00        ;; Loop to try again
;;                                         Fall through to try once more
.L8B09 LDX #<(ABSWS+&0215) ;; Point to control block
       LDY #>(ABSWS+&0215)
       STX &B0
       STY &B1
       LDX ABSWS+&0219  ;; Get Addr3
       LDA ABSWS+&0218  ;; Get Addr2
       SHADOW_SELECT    ;; Check for shadow screen memory
       LDA ABSWS+&0317  ;; Get current drive
       ORA ABSWS+&021B  ;; OR with drive number
       STA ABSWS+&021B  ;; Store back into control block
       STA ABSWS+&0333
IF INCLUDE_FLOPPY
       LDA &CD          ;; Get options
       AND #&20         ;; Hard drive present?
       BNE L8B4F        ;; Jump ahead if so
.L8B2C LDA ABSWS+&021B
       ORA ABSWS+&0317
       STA ABSWS+&02D2
       LDA ABSWS+&021C
       STA ABSWS+&02D1
       LDA ABSWS+&021D
       STA ABSWS+&02D0
       JSR LACE6
       STA ABSWS+&0204,X
       TXA
       LSR A
       LSR A
       ADC #&C9
       JMP LBA4E
ENDIF
;;
;; Get bytes from a partial sector from a hard drive
;; -------------------------------------------------
.L8B4F LDA ABSWS+&0333  ;; Get drive number
IF INCLUDE_FLOPPY
       BMI L8B2C        ;; Jump back with floppies
ENDIF
       JSR L807E        ;; Set SCSI to command mode
       LDA ABSWS+&0216
       STA &B2
       LDA ABSWS+&0217
       STA &B3          ;; &B2/3=address b0-b15
       LDA ABSWS+&0218  ;; Get Addr2
       CMP #&FE
       BCC L8B6E        ;; Addr<&FFFE0000, language space
       LDA ABSWS+&0219  ;; Get Addr3
       INC A
       BEQ L8B71        ;; Address &FFxxxxxx, use I/O memory
.L8B6E JSR L8020        ;; Claim Tube
.L8B71 LDA ABSWS+&021E  ;; Get byte count (in Sector Count)
       TAX              ;; Pass to X
       LDA #&01
       STA ABSWS+&021E  ;; Set Sector Count to 1
       LDA #&08
       STA ABSWS+&021A  ;; Command &08 - Read
IF PATCH_SD
       JSR MMC_BEGIN    ;; Initialize the card, if not already initialized
       CLC              ;; C=0 for reads
       JSR MMC_SetupRW  ;; Setup SD card command block        
       JSR setCommandAddress
ELIF PATCH_IDE
       PHX             ;; Load a partial sector
       JSR SetGeometry ;; Pass sector address to IDE
       JSR SetSector
       PLX
       NOP
       NOP
       NOP
       NOP
       NOP
ELSE
       LDY #&00
.L8B81 LDA ABSWS+&021A,Y
       JSR L833E        ;; Send control block to SCSI
       INY
       CPY #&06
       BNE L8B81
ENDIF
       BIT &CD          ;; Check Tube flags
       BVC L8B9B        ;; Tube not being used, jump ahead
       PHX              ;; Save byte count in X
       LDX #<(ABSWS+&0227)
       LDY #>(ABSWS+&0227)
       LDA #&01
       JSR &0406        ;; Set Tube transfer address
       PLX              ;; Get byte count back
IF PATCH_SD
.L8B9B PHX
       JSR MMC_StartRead
       PLX
       PHX
       JSR MMC_ReadX
       PLA
	   EOR #&FF         ;; Calculate 256 - bytecount
	   TAY
	   INY
       JSR MMC_Clocks	;; ignore rest of sector
       JSR MMC_Clocks	;; twice, as sectors are stretched to 512 bytes
       JSR MMC_16Clocks	;; ignore CRC
       ;; TODO Add error handling
ELSE
.L8B9B LDY #&00         ;; Fetch 256 bytes
       JSR L8332        ;; Wait for SCSI ready
       BMI L8BBB        ;; Jump ahead if switched to write
.L8BA2 LDA &FC40        ;; Get byte from SCSI
       CPX #&00         ;; No more bytes left?
       BEQ L8BB8        ;; Jump to ignore extra bytes
       BIT &CD          ;; Tube or I/O?
       BVC L8BB5        ;; Jump to read to I/O memory
       JSR L821B        ;; Pause a bit
       STA &FEE5        ;; Send to Tube
       BVS L8BB7        ;; Jump ahead to loop back
.L8BB5 STA (&B2),Y      ;; Store byte to I/O
.L8BB7 DEX              ;; Decrement byte count
.L8BB8 INY              ;; Next byte to fetch
       BNE L8BA2        ;; Loop for all 256 bytes
ENDIF
;;
.L8BBB JMP L81AD        ;; Jump to release and finish
;;
.L8BBE JSR L8870
       BEQ L8BCA
       BNE L8BD2
.L8BC5 JSR L8964
       BNE L8BD2
.L8BCA LDY #&03
       LDA (&B6),Y
       BMI L8BC5
.L8BD0 LDA #&00
.L8BD2 RTS
;;
.L8BD3 LDY #&00
       LDA (&B4),Y
       CMP #&5E
       BNE L8BDE
.L8BDB JMP L8760
;;
.L8BDE CMP #&40
       BEQ L8BDB
.L8BE2 JSR L836B
       EQUB &D6         ;; ERR=210
       EQUS "Not found"
       EQUB &00
;;
;; Search for object, give error if 'E' set
;; ========================================
.L8BF0 JSR L8FE8        ;; Search for object
       BNE L8BD2        ;; Not found, return NE
       LDY #&04
       LDA (&B6),Y      ;; Check 'E' bit
       BPL L8BD0        ;; Not 'E', return EQ for found
.L8BFB JSR L836B        ;; Error 'Access violation'
       EQUB &BD         ;; ERR=189
       EQUS "Access violation"
       EQUB &00
;; OSFILE &FF - LOAD
;; =================
.L8C10 JSR L8BBE
       BNE L8BD3
       LDY #&00
       LDA (&B6),Y
       BPL L8BFB
.L8C1B LDY #&06
       LDA (&B8),Y
       BNE L8C2E
       DEY
.L8C22 LDA (&B8),Y
       STA ABSWS+&0214,Y
       DEY
       CPY #&01
       BNE L8C22
       BEQ L8C3B
.L8C2E LDX #&04
       LDY #&0D
.L8C32 LDA (&B6),Y
       STA ABSWS+&0215,X
       DEY
       DEX
       BNE L8C32
.L8C3B LDA #&01
       STA ABSWS+&0215  ;; Set flag byte to 1
       LDA #&08
       STA ABSWS+&021A  ;; Command 'read'
       LDA #&00
       STA ABSWS+&021F
       LDY #&16
       LDX #&03
.L8C4E LDA (&B6),Y
       STA ABSWS+&021A,X ;; Copy sector start
       INY
       DEX
       BNE L8C4E
       LDY #&15
       LDX #&04
.L8C5B LDA (&B6),Y
       STA ABSWS+&021F,X ;; Copy length
       DEY
       DEX
       BNE L8C5B
       JSR L8A42
.L8C67 JSR L8C6D
       JMP L89D5
;;
.L8C6D JSR L9501        ;; Print info if *OPT1 set
;;
;; Copy file info to control block
;; -------------------------------
.L8C70 LDY #&15         ;; Top byte of length
       LDX #&0B         ;; 11+1 bytes to copy
.L8C74 LDA (&B6),Y      ;; Copy length/exec/load
       STA ABSWS+&0215,X ;;  to workspace
       DEY
       DEX
       BPL L8C74        ;; Loop for 12 bytes
       LDY #&0D
       LDX #&0B
.L8C81 LDA ABSWS+&0215,X ;; Copy from workspace
       STA (&B8),Y      ;;  to control block
       DEY
       DEX
       BPL L8C81        ;; Loop for 12 bytes
IF PATCH_FULL_ACCESS
       LDY #8
.RdLp
       CPY #4           ;; Read full access byte
       BNE RdNotE
       DEY
       DEY
.RdNotE
       LDA (&B6),Y
       ASL A
       ROL ABSWS+&022B
       CPY #4
       BEQ RdIsE
       CPY #2
       BNE RdNext
       INY
       INY
       BRA RdNotE
.RdIsE
       DEY
       DEY
.RdNext
       DEY
       BPL RdLp
       LDA ABSWS+&022B
       LDY #&0E
       STA (&B8),Y
       RTS
       NOP
       NOP
ELSE
       LDA #&00
       STA ABSWS+&022B  ;; Clear byte for access
       LDY #&02         ;; Point to 'L' bit
.L8C91 LDA (&B6),Y
       ASL A
       ROL ABSWS+&022B  ;; Copy LWR into &C22B
       DEY
       BPL L8C91
       LDA ABSWS+&022B  ;; A=00000LWR
       ROR A            ;; A=000000LW Cy=R
       ROR A            ;; A=R000000L Cy=W
       ROR A            ;; A=WR000000 Cy=L
       PHP              ;; Save 'L'
       LSR A            ;; A=0WR00000
       PLP              ;; Get 'L'
       ROR A            ;; A=L0WR0000
       STA ABSWS+&022B  ;; Store back in workspace
       LSR A
       LSR A
       LSR A
       LSR A            ;; A=0000L0WR
       ORA ABSWS+&022B  ;; A=L0WRL0WR
       LDY #&0E
       STA (&B8),Y      ;; Store access byte in control block
       RTS
ENDIF
;;
;; OSFILE &05 - Read Info
;; ======================
;; &B8/9=>control block, &B4/5=>filename
;;
.L8CB3 LDY #&00         ;; Copy filename address again
       LDA (&B8),Y
       STA &B4
       INY
       LDA (&B8),Y
       STA &B5
       JSR L8FE8        ;; Search for object
       BNE L8CD1
       LDY #&04
       LDA (&B6),Y      ;; Get 'E' bit
       BPL L8CCE        ;; 'E' not set, jump
       LDA #&FF         ;; 'E' set, filetype &FF
IF PATCH_FULL_ACCESS
       STA ABSWS+&02C0
ELSE
       JMP L89D8        ;;                         STA &C2C0
ENDIF
;;
.L8CCE JSR L8C70
.L8CD1 JMP L89D5
;;
.L8CD4 LDY #&00
       LDA (&B8),Y
       STA &B4
       INY
       LDA (&B8),Y
       STA &B5
       JSR L8DC8
       JSR L8FE8
       BEQ L8CEC
       JSR L9456
       BEQ L8D01
.L8CEC RTS
;;
.L8CED JSR L8CD4
       BEQ L8D1B
       BNE L8CF9
.L8CF4 JSR L8CD4
       BEQ L8D12
.L8CF9 LDY #&00
.L8CFB LDA (&B4),Y
       CMP #&2E
       BNE L8D04
.L8D01 JMP L8BD3
;;
.L8D04 CMP #&21
       BCC L8D0F
       CMP #&22
       BEQ L8D0F
       INY
       BNE L8CFB
.L8D0F LDA #&11
       RTS
;;
.L8D12 LDY #&03
       LDA (&B6),Y
       BPL L8D1B
       JMP L95AB
;;
.L8D1B LDY #&02
       LDA (&B6),Y
       BPL L8D2C
       JSR L836B
       EQUB &C3         ;; ERR=195
       EQUS "Locked"
       EQUB &00
;;
.L8D2C LDX #&09
.L8D2E LDA ABSWS+&03AC,X
       BEQ L8D74
       LDA ABSWS+&03B6,X
       AND #&E0
       CMP ABSWS+&0317
       BNE L8D74
       LDA ABSWS+&03E8,X
       CMP ABSWS+&0314
       BNE L8D74
       LDA ABSWS+&03DE,X
       CMP ABSWS+&0315
       BNE L8D74
       LDA ABSWS+&03D4,X
       CMP ABSWS+&0316
       BNE L8D74
       LDY #&19
       LDA (&B6),Y
       CMP ABSWS+&03F2,X
       BNE L8D74
.L8D5E JSR L836B
       EQUB &C2         ;; ERR=194
       EQUS "Can't - File open"
       EQUB &00
;;
.L8D74 DEX
       BPL L8D2E
       INX
       RTS
;;
.L8D79 LDY #&00
       JSR L8743
       BNE L8D85
       CMP #&2E
       BEQ L8DE6
       RTS
;;
.L8D85 CMP #&3A
       BNE L8D98
       INY
.L8D8A INY
       JSR L8743
       BNE L8DE6
       CMP #&2E
       BNE L8DE0
       INY
       JSR L8DE1
.L8D98 AND #&FD
       CMP #&24
       BEQ L8D8A
.L8D9E JSR L8DE1
       CMP #&5E
       BEQ L8DA9
       CMP #&40
       BNE L8DB6
.L8DA9 INY
       JSR L8743
       BNE L8DE6
.L8DAF CMP #&2E
       BNE L8DE0
       INY
       BRA L8D9E
;;
.L8DB6 JSR L8743
       BEQ L8DAF
       LDX #&05
.L8DBD CMP L8DF8,X
       BEQ L8DE6
       DEX
       BPL L8DBD
       INY
       BNE L8DB6
.L8DC8 JSR L8D79
.L8DCB LDA (&B4),Y
       AND #&7F
       CMP #&2A
       BEQ L8DE9
       CMP #&23
       BEQ L8DE9
       CMP #&2E
       BEQ L8DE0
       DEY
       CPY #&FF
       BNE L8DCB
.L8DE0 RTS
;;
.L8DE1 JSR L8743
       BNE L8DE0
.L8DE6 JMP L8760
;;
.L8DE9 JSR L836B
       EQUB &Fd         ;; ERR=194
       EQUS "Wild cards"
       EQUB &00
;;
.L8DF8 EQUS &7F, "^@:$&"
;;
.L8DFE JSR L8CF4
.L8E01 BNE L8E24
       LDX #&02
       LDY #&12
       LDA (&B6),Y
       CMP #&01
.L8E0B INY
       LDA #&00
       ADC (&B6),Y
       STA ABSWS+&0224,Y
       DEX
       BPL L8E0B
       LDY #&18
       LDX #&02
.L8E1A LDA (&B6),Y
       STA ABSWS+&0234,X
       DEY
       DEX
       BPL L8E1A
       RTS
;;
.L8E24 LDA ABSWS+&08B1
       BEQ L8E36
       JSR L836B
       EQUB &B3         ;; ERR=179
       EQUS "Dir full"
       EQUB &00
;;
.L8E36 LDA &B4
       STA ABSWS+&0227
       LDA &B5
       STA ABSWS+&0228
       LDA #&B1
       STA &B4
       LDA #&C8
       STA &B5
       LDY #&1A
       LDX #&06
       LDA #&00
.L8E4E STA ABSWS+&0233,X
       DEX
       BNE L8E4E
.L8E54 LDA (&B4,X)
       STA (&B4),Y
       LDA &B4
       CMP &B6
       BNE L8E64
       LDA &B5
       CMP &B7
       BEQ L8E6F
.L8E64 LDA &B4
       BNE L8E6A
       DEC &B5
.L8E6A DEC &B4
       JMP L8E54
;;
.L8E6F LDA ABSWS+&0227
       STA &B4
       LDA ABSWS+&0228
       STA &B5
       RTS
;;
.L8E7A LDY #&09
.L8E7C LDA (&B4),Y
       AND #&7F
       CMP #&21
       BCC L8E88
       CMP #&22
       BNE L8E8A
.L8E88 LDA #&0D
.L8E8A CPY #&02
       BCS L8E90
       ORA #&80
.L8E90 STA (&B6),Y
       DEY
       BPL L8E7C
       RTS
;;
.L8E96 LDY #&11
.L8E98 LDA (&B8),Y
       STA ABSWS+&0215,Y
       DEY
       BPL L8E98
       LDY #&12
       SEC
       LDX #&03
.L8EA5 LDA ABSWS+&0211,Y
       SBC ABSWS+&020D,Y
       STA (&B6),Y
       INY
       DEX
       BPL L8EA5
       LDY #&0A
.L8EB3 LDA ABSWS+&020D,Y
       STA (&B6),Y
       INY
       CPY #&12
       BNE L8EB3
       LDA &B6
       PHA
       LDA &B7
       PHA
.L8EC3 LDA #&05
       STA &B6
       LDA #&C4
       STA &B7
.L8ECB LDY #&00
       LDA (&B6),Y
       BEQ L8EF8
       LDY #&19
       LDA (&B6),Y
       CMP ABSWS+&08FA
       BEQ L8EE7
       CLC
       LDA &B6
       ADC #&1A
       STA &B6
       BCC L8ECB
       INC &B7
       BCS L8ECB
.L8EE7 LDA ABSWS+&08FA
       CLC
       SED
       ADC #&01
       CLD
       STA ABSWS+&08FA
       STA ABSWS+&0400
       JMP L8EC3
;;
.L8EF8 PLA
       STA &B7
       PLA
       STA &B6
       LDY #&19
       LDA ABSWS+&08FA
       STA (&B6),Y
       LDA #&01
       STA ABSWS+&0215
       LDX #&04
.L8F0C LDA ABSWS+&021E,X
       STA ABSWS+&0215,X
       DEX
       BNE L8F0C
       LDA #&0A
       STA ABSWS+&021A
       LDA #&00
       STA ABSWS+&021E
       LDA #&00
       STA ABSWS+&021F
       LDY #&12
.L8F26 LDA (&B6),Y
       STA ABSWS+&020E,Y
       INY
       CPY #&16
       BNE L8F26
       LDY #&12
       LDA (&B6),Y
       CMP #&01
       LDX #&02
.L8F38 LDA #&00
       INY
       ADC (&B6),Y
       STA ABSWS+&022A,Y
       DEX
       BPL L8F38
       BCC L8F48
       JMP L867F
;;
.L8F48 LDY #&16
       LDA #&FF
       STA (&B6),Y
       INY
       STA (&B6),Y
       INY
       STA (&B6),Y
       JMP L84E1
;;
.L8F57 JSR L8DFE
       JSR L8E7A
.L8F5D JSR L8E96
       JSR L865B
.L8F63 LDY #&18
       LDX #&02
.L8F67 LDA ABSWS+&023A,X
       STA (&B6),Y
       DEY
       DEX
       BPL L8F67
       LDX #&02
       LDY #&06
.L8F74 LDA ABSWS+&023A,X
       STA ABSWS+&0215,Y
       INY
       DEX
       BPL L8F74
       RTS
;;
.L8F7F JSR L8F57
       JSR L8A42
       JMP L8F8B
;;
.L8F88 JSR L8F57
.L8F8B JSR L8F91
       JMP L8C67
;;
.L8F91 JSR LA714
       JSR L9012
       LDX #&0A
.L8F99 LDA L883C,X
       STA ABSWS+&0215,X
       DEX
       BPL L8F99
       LDA #&0A
       STA ABSWS+&021A
       LDA ABSWS+&0314
       STA ABSWS+&021D
       LDA ABSWS+&0315
       STA ABSWS+&021C
       LDA ABSWS+&0316
       STA ABSWS+&021B
       JSR L82AA
       LDA ABSWS+&0317
       JSR LB5C5        ;; X=(A DIV 16)
       LDA ABSWS+&01FC
       STA ABSWS+&0322,X
       LDA &FE44        ;; System VIA Latch Lo
       STA ABSWS+&0321,X
       STA ABSWS+&01FB
       JSR L9065        ;; Calculate FSM checksums
       STX ABSWS+&00FF  ;; Store sector 0 checksum
       STA ABSWS+&01FF  ; Store sector 1 checksum
       LDX #<L907A      ;; Point to control block
       LDY #>L907A
       JSR L82AE        ;; Save FSM
       LDA #&10
       TRB &CD          ;; Flag FSM loaded
       LDA #&00
       RTS
;;
.L8FE8 JSR L8870
       PHP
       PHA              ;; Save registers
       JSR L8FF3        ;; Check loaded FSM
       PLA              ;; Restore registers
       PLP
.L8FF2 RTS
;;
;; Check Free Space Map consistancy
;; ================================
IF PATCH_IDE
.L8FF3 RTS              ;; Bodge 'Bad FS map' check
       EQUB <L9012      ;; Junk - so a binary compare will pass
       EQUB >L9012      ;; Junk - so a binary compare will pass
ELSE
.L8FF3 JSR L9012        ;; Check for overlapping FSM entries
ENDIF
       JSR L9065        ;; Add up
       CMP ABSWS+&01FF  ;; Does sector 1 sum match?
       BNE L9003        ;; No, jump to give error
       CPX ABSWS+&00FF  ;; Does sector 0 sum match?
       BEQ L8FF2        ;; Yes, exit
.L9003 JSR L834E        ;; Generate error
       EQUB &A9         ;; ERR=169
       EQUS "Bad FS map"
       EQUB &00
;;
;; Check Free Space Map doesn't have overlapping entries
;; -----------------------------------------------------
.L9012 LDX ABSWS+&01FE  ;; Get pointer to end of FSM
       BEQ L8FF2        ;; Pointer=0, disk completely full, exit
       LDA #&00         ;; Seed the sum with zero
.L9019 ORA ABSWS-1,X    ;; Merge with high byte of final free space
       ORA ABSWS+&00FF,X ;; Merge with high byte of final length
       DEX
       BEQ L9003        ;; Give error if end pointer not *3
       DEX
       BEQ L9003        ;; Give error if end pointer not *3
       DEX
       BNE L9019        ;; Multiple of three, check net entry
       AND #&E0         ;; Get "drive" bits
       BNE L9003        ;; If any set, map entry too big
       LDX ABSWS+&01FE  ;; Get pointer to end of FSM
       CPX #&06         ;; Are there two or more entries?
       BCC L8FF2        ;; Exit if only one FSM entry
       LDX #&03         ;; Point to first entry minus 3
.L9035 LDY #&02         ;; Three bytes per entry
       CLC              ;; Clear carry
.L9038 LDA ABSWS-3,X    ;; Get FSM entry start sector
       ADC ABSWS+&00FD,X ;; Add FSM entry length
       PHA              ;; Save byte
       INX              ;; Point to next byte
       DEY
       BPL L9038        ;; Loop for three bytes
       BCS L9003        ;; Start+Length overflowed, give error
       LDY #&02         ;; Three bytes per entry
.L9047 PLA              ;; Get start+length byte
       DEX
       CMP ABSWS+&0000,X ;; Check against next entry start
       BCC L9055        ;; Hole in FSM, check next byte
       BNE L9003        ;; Entry overlaps, give error
       DEY
       BPL L9047        ;; Loop for three bytes
       BMI L9003        ;; Entry overlaps, give error
.L9055 PLA              ;; Get next byte
       DEX
       DEY
       BPL L9055
       PHA
       INX
       INX
       INX
       INX              ;; Point to next entry
       CPX ABSWS+&01FE  ;; Check against end of FSM
       BCC L9035        ;; Loop for all entries
       RTS
;;
;; Add up FSM
;; ----------
.L9065 CLC              ;; Clear carry
       LDY #&FF         ;; Point to &xxFE
       TYA              ;; Initialise A with -1
.L9069 ADC ABSWS-1,Y    ;; Add sector 0 bytes &FE to &00
       DEY
       BNE L9069        ;; Loop for all bytes
       TAX              ;; Save result in X
       DEY              ;; Reset Y to &FF again
       TYA              ;; Initialise A with -1
       CLC              ;; Clear carry
.L9073 ADC ABSWS+&00FF,Y ;; Add sector 1 bytes from &FE to &00
       DEY
       BNE L9073        ;; Loop for all bytes
       RTS
;;
;; Control block to save FSM
.L907A EQUB &01
       EQUB <ABSWS
       EQUB >ABSWS
       EQUB &FF
       EQUB &FF
       EQUB &0A
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &02
       EQUB &00
;;
;; OSFILE &01-&03 - Write Info
;; ===========================
.L9085 STA ABSWS+&0223  ;; Save function
IF PATCH_FULL_ACCESS
       JSR L8FE8
ELSE
       JSR L8BF0        ;; Search for non-'E' object
ENDIF
       BEQ L9090        ;; Jump if file found
       LDA #&00         ;; Return 'no file'
       RTS
;;
;; Write Info - file found
;; -----------------------
;; (&B6)=>file info, (&B8)=>control block
.L9090 LDA ABSWS+&0223  ;; Get OSFILE function
       CMP #&03
       BEQ L90B8        ;; Jump past with Exec
       LDY #&05
       LDX #&03
.L909B LDA (&B8),Y
       STA ABSWS+&0215,X
       DEY
       DEX
       BPL L909B
       LDY #&0D
       LDX #&03
.L90A8 LDA ABSWS+&0215,X
       STA (&B6),Y
       DEY
       DEX
       BPL L90A8
       LDA ABSWS+&0223
       CMP #&02
       BEQ L9104
.L90B8 LDY #&09
       LDX #&03
.L90BC LDA (&B8),Y
       STA ABSWS+&0215,X
       DEY
       DEX
       BPL L90BC
       LDY #&11
       LDX #&03
.L90C9 LDA ABSWS+&0215,X
       STA (&B6),Y
       DEY
       DEX
       BPL L90C9
       LDX ABSWS+&0223
       DEX
       BNE L9104
;;
.L90D8 LDY #&0E
       LDA (&B8),Y      ;; Get access byte
       STA ABSWS+&022B
IF PATCH_FULL_ACCESS
       LDY #8
.WrLp
        CPY #4         ;; Write full access byte
        BNE WrNotE
        DEY
        DEY
.WrNotE
        LDA (&B6),Y
        ASL A
        ROL ABSWS+&022B
        ROR A
        STA (&B6),Y
        CPY #4
        BEQ WrIsE
        CPY #2
        BNE WrNext
        INY
        INY
        BRA WrNotE
.WrIsE
        DEY
        DEY
.WrNext
        DEY
        BPL WrLp
        NOP
        NOP
        NOP
ELSE
       LDY #&03
       LDA (&B6),Y      ;; Check 'D' bit
       BPL L90F2        ;; Jump if a file
       LSR ABSWS+&022B
       LSR ABSWS+&022B
.L90EB LSR ABSWS+&022B        ;; Move 'L' bit down to b0
       LDY #&02         ;; Point to 'L' bit
       BPL L90F4
;;
.L90F2 LDY #&00         ;; Point to 'R' bit
;;
.L90F4 LDA (&B6),Y      ;; Get filename byte
       ASL A            ;; Drop access bit
       LSR ABSWS+&022B        ;; Get supplied access bit
       ROR A            ;; Move into filename byte
       STA (&B6),Y      ;; Store in object info
       INY              ;; Step to next byte
       CPY #&02
       BCC L90F4        ;; Loop until RW done
       BEQ L90EB        ;; 'L' bit, move source down one more bit
ENDIF
.L9104 JSR L8F91        ;; RWL done, store catalogue entry
       JMP L8CCE
;;
;; OSFILE &04 - Write Attributes
;; =============================
IF PATCH_FULL_ACCESS
.L910A JSR L8FE8
ELSE
.L910A JSR L8BF0
ENDIF
       BEQ L90D8
       LDA #&00
       RTS
;;
       JSR LA50D
       LDA &B4
       STA ABSWS+&0240
       LDA &B5
       STA ABSWS+&0241
       LDA #<(ABSWS+&0240)
       STA &B8
       LDA #>(ABSWS+&0240)
       STA &B9
.L9127 JSR L8CD4
       BEQ L9131
       LDA #&00
       JMP L89D8
;;
.L9131 JSR L8D1B
       LDY #&03
       LDA (&B6),Y
       BPL L9177
       LDY #&03
.L913C LDA ABSWS+&022C,Y
       STA ABSWS+&0230,Y
       DEY
       BPL L913C
       LDA #&FF
       STA ABSWS+&022E
       STA ABSWS+&022F
       JSR L9486
       LDA ABSWS+&0405
       PHP
       JSR L89D8
       LDY #&03
.L9159 LDA ABSWS+&0230,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L9159
       PLP
       BEQ L9177
       JSR L836B
       EQUB &B4         ;; ERR=180
       EQUS "Dir not empty"
       EQUB &00
;;
.L9177 LDY #&12
       LDX #&02
       LDA (&B6),Y
       CMP #&01
.L917F INY
       LDA #&00
       ADC (&B6),Y
       STA ABSWS+&0224,Y
       DEX
       BPL L917F
       LDY #&18
       LDX #&02
.L918E LDA (&B6),Y
       STA ABSWS+&0234,X
       DEY
       DEX
       BPL L918E
       LDY #&03
       LDA (&B6),Y
       BPL L921B
       LDX ABSWS+&022F
       CPX #&FF
       BEQ L91A9
       CPX ABSWS+&0317
       BNE L91CB
.L91A9 LDX #&02
.L91AB LDA ABSWS+&0234,X
       CMP ABSWS+&022C,X
       BNE L91CB
       DEX
       BPL L91AB
       JSR L836B
       EQUB &96         ;; ERR=150
       EQUS "Can't delete CSD"
       EQUB &00
;;
.L91CB LDA ABSWS+&0317
       CMP ABSWS+&031B
       BNE L91F9
       LDX #&02
.L91D5 LDA ABSWS+&0234,X
       CMP ABSWS+&0318,X
       BNE L91F9
       DEX
       BPL L91D5
       JSR L836B
       EQUB &97         ;; ERR=151
       EQUS "Can't delete Library"
       EQUB &00
;;
.L91F9 LDA ABSWS+&0317
       CMP ABSWS+&031F
       BNE L921B
       LDX #&02
.L9203 LDA ABSWS+&0234,X
       CMP ABSWS+&031C,X
       BNE L921B
       DEX
       BPL L9203
       LDA #&02
       STA ABSWS+&031C
       LDA #&00
       STA ABSWS+&031D
       STA ABSWS+&031E
.L921B LDY #&04
       LDA (&B6),Y
       BMI L9224
       JSR L8C70
.L9224 LDY #&1A
       LDX #&00
.L9228 LDA (&B6),Y
       STA (&B6,X)
       INC &B6
       BNE L9232
       INC &B7
.L9232 LDA &B6
       CMP #&BB
       BNE L9228
       LDA &B7
       CMP #&C8
       BNE L9228
       JSR L84E1
       JSR L8F91
       JMP L89D5
;;
;;
;; OSFILE
;; ======
;; A=function, XY=>control block
;; -----------------------------
.L9247 STX &B8          ;; Store pointer to control block
       STY &B9
       TAY              ;; Y=function                  Unsupported should return A preserved:
;;                                                                     NOP
IF PATCH_UNSUPPORTED_OSFILE
       NOP              ;; Unsupported OSFILE returns A preserved
       CLR ABSWS+&02D5
       ASL A
       TAX
       TYA
ELSE
       LDX #&00         ;;                             CLR &C2D5
       STX ABSWS+&02D5        ;;                             ASL A
       ASL A            ;; Index into dispatch table   TAX
       TAX              ;;                             TYA
ENDIF
       INX              ;;                             INX
       INX              ;;                             INX
       BMI L9270        ;; <&FF, return with A=func*2  BMI L9270
       CPX #&12
       BCS L9270        ;; >&07, return with A=func*2
       LDA L9271+1,X      ;; Get dispatch address
       PHA
       LDA L9271,X
       PHA
       PHY              ;; Stack function
       LDY #&00         ;; Get filename address
       LDA (&B8),Y
       STA &B4
       INY
       LDA (&B8),Y
       STA &B5          ;; &B4/5=>filename
       PLA              ;; Get function to A
.L9270 RTS              ;; Jump to subroutine
;;
;; On dispatch, (&B8)=>control block, (&B4)=>filename, A=function, Y=1, X=corrupted
;; Subroutine should return A=filetype, XY=>control block
;;
;;
;; OSFILE Dispatch Block
;; =====================
.L9271 EQUW L8C10-1 ; &FF - LOAD
       EQUW L8F7F-1 ; &00 - SAVE
       EQUW L9085-1 ; &01 - Write Info
       EQUW L9085-1 ; &02 - Write Load
       EQUW L9085-1 ; &03 - Write Exec
       EQUW L910A-1 ; &04 - Write Attrs
       EQUW L8CB3-1 ; &05 - Read Info
       EQUW L9127-1 ; &06 - Delete
       EQUW L8F88-1 ; &07 - Create
;;
.L9283 TAX
       LDA #>L9FB1
       STA &B7
       LDA L9E95,X
       STA &B6
       LDX #&0C
;;
.L928F LDY #&00
.L9291 LDA (&B6),Y
       AND #&7F
       CMP #&20
       BCC L92A1
       JSR L92CB
       INY
       DEX
       BNE L9291
       RTS
;;
.L92A1 JSR LA036
       DEX
       BNE L92A1
       RTS
;;
.L92A8 PLA
       STA &B6
       PLA
       STA &B7
       LDY #&01
.L92B0 LDA (&B6),Y
       BMI L92BA
       JSR L92CB
       INY
       BNE L92B0
.L92BA AND #&7F
       JSR L92CB
       TYA
       CLC
       ADC &B6
       TAY
       LDA #&00
       ADC &B7
       PHA
       PHY
       RTS
;;
.L92CB PHA
       TXA
       PHA
       LDA &B6
       PHA
       LDA &B7
       PHA
       TSX
       LDA &0104,X
       JSR LA03C
       PLA
       STA &B7
       PLA
       STA &B6
       PLA
       TAX
       PLA
       RTS
;;
;; Print filename, access, cycle number
;; ====================================
.L92E5 LDX #&0A
       JSR L928F
       JSR LA036
       LDY #&04         ;; Point to access bits
       LDX #&03         ;; Allow three characters padding
.L92F1 LDA (&B6),Y      ;; Get access bit
       ROL A
       BCC L92FD        ;; Not set, step to next one
       LDA L931D,Y      ;; Get access character
       JSR LA03C        ;; Print it
       DEX              ;; Dec. padding needed
;;
.L92FD DEY              ;; Step to next access bit
       BPL L92F1        ;; Loop until <0
.L9300 DEX              ;; Dec. padding needed
       BMI L9309        ;; All done
       JSR LA036        ;; Print a space
       JMP L9300        ;; Loop to print padding
;;
.L9309 LDA #&28
       JSR LA03C        ;; Print '('
       LDY #&19
       LDA (&B6),Y      ;; Get cycle number
       JSR L9322        ;; Print it
       LDA #&29
       JSR LA03C        ;; Print ')'
       JMP LA036        ;; Finish with a space
;;
;; Access bits
;; ===========
.L931D EQUS "RWLDE"
;;
.L9322 PHA
       LSR A
       LSR A
       LSR A
       LSR A
       JSR L932B
       PLA
.L932B JSR L8462
       JMP LA03C
;;
.L9331 JSR LA714
       LDA #<(ABSWS+&08D9)
       STA &B6
       LDA #>(ABSWS+&08D9)
       STA &B7
       LDX #&13
       JSR L928F
       JSR L92A8
       EQUB &20, &A8
       LDA ABSWS+&08FA
       JSR L9322
       JSR L92A8
       EQUS ")",&0D,"Drive",&BA
       LDA ABSWS+&0317
       ASL A
       ROL A
       ROL A
       ROL A
       ADC #&30
       JSR LA03C
       LDA #<L9A68
       STA &B6
       LDA #>L9A68
       STA &B7
       LDX #&0D
       JSR L928F
       JSR L92A8
       EQUS "Option", &A0
       LDA ABSWS+&01FD
       JSR L9322
       JSR L92A8
       EQUB &20, &A8
       LDX ABSWS+&01FD
       LDA L9426,X
       STA &B6
       LDA #>L9426
       STA &B7
       LDX #&04
       JSR L928F
       JSR L92A8
       EQUS ")",&0D,"Dir.",&A0
       LDA #<(ABSWS+&0300)
       STA &B6
       LDA #>(ABSWS+&0300)
       STA &B7
       LDX #&0A
       JSR L928F
       JSR L92A8
       EQUS "     Lib.",&A0
       LDA #<(ABSWS+&030A)
       STA &B6
       LDA #>(ABSWS+&030A)
       STA &B7
       LDX #&0A
       JSR L928F
       JSR L92A8
       EQUB &0D,&8D
.L93CC LDA #<(ABSWS+&0405)
       STA &B6
       LDA #>(ABSWS+&0405)
       STA &B7
       RTS
;;
;; FSC 5 - *CAT
;; ============
.L93D5 JSR LA50D
       JSR L9478
.L93DB JSR L9331
       LDA #&04
       STA ABSWS+&022B
.L93E3 LDY #&00
       LDA (&B6),Y
       BEQ L940C
       JSR L92E5
       DEC ABSWS+&022B
       BNE L93FC
       LDA #&04
       STA ABSWS+&022B
       JSR LA03A
       JMP L93FF
;;
.L93FC JSR LA036
.L93FF CLC
       LDA &B6
       ADC #&1A
       STA &B6
       BCC L93E3
       INC &B7
       BCS L93E3
.L940C LDA ABSWS+&022B
       CMP #&04
       BEQ L9423
       LDA #&86
       JSR &FFF4
       TXA
       BNE L9420
       LDA #&0B
       JSR LA03C
.L9420 JSR LA03A
.L9423 JMP L89D8
;;
.L9426 EQUB <L942A, <L942E, <L9432, <L9436
.L942A EQUS "Off "
.L942E EQUS "Load"
.L9432 EQUS "Run "
.L9436 EQUS "Exec"
;;
;; FSC 9 - *EX
;; =============
.L943A JSR L9478
.L943D JSR L9331
.L9440 LDY #&00
       LDA (&B6),Y
       BEQ L9423
       JSR L9508
       CLC
       LDA &B6
       ADC #&1A
       STA &B6
       BCC L9440
       INC &B7
       BRA L9440
;;
.L9456 LDY #&00
       LDA (&B4),Y
       AND #&7F
       CMP #&5E
       BNE L946A
       LDA #<(ABSWS+&08C0)
       STA &B6
       LDA #>(ABSWS+&08C0)
       STA &B7
       BNE L9476
.L946A CMP #&40
       BNE L9477
       LDA #<(ABSWS+&02FE)
       STA &B6
       LDA #>(ABSWS+&02FE)
       STA &B7
.L9476 TYA
.L9477 RTS
;;
.L9478 LDY #&00
       LDA (&B4),Y
       CMP #&21
       BCS L9486
       LDX ABSWS+&0317
       INX
       BNE L9477
.L9486 JSR L8875
       BNE L9499
.L948B LDY #&03
       LDA (&B6),Y
       BMI L949E
       JSR L8964
       BEQ L948B
.L9496 JMP L8BE2        ;; Not Found error
;;
.L9499 JSR L9456
       BNE L9496
.L949E LDY ABSWS+&022E
       INY
       BNE L94AF
       LDY #&02
.L94A6 LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L94A6
.L94AF LDX #&0A
.L94B1 LDA L883C,X
       STA ABSWS+&0215,X
       DEX
       BPL L94B1
       LDX #&02
       LDY #&16
.L94BE LDA (&B6),Y
       STA ABSWS+&021B,X
       STA ABSWS+&02FE,Y
       INY
       DEX
       BPL L94BE
       LDA &B7
       CMP #&94
       BEQ L9507
       JMP L82AA
;;
;; Fake entry for '$'
;; ==================
.L94D3 EQUB &A4
       EQUB &0D
       EQUB &8D
       EQUB &8D
       EQUB &0D
       EQUB &0D
       EQUB &0D
       EQUB &0D
       EQUB &0D
       EQUB &0D
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &05
       EQUB &00
       EQUB &00
       EQUB &02
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
;;
;; FSC 10 - *INFO
;; ==============
.L94EE JSR L8FE8        ;; Search for object
       BEQ L94F6
       JMP L8BD3        ;; Error 'File not found' or 'Bad name'
;;
.L94F6 JSR L9508        ;; Call ...
       JSR L8964
       BEQ L94F6
       JMP L89D8
;;
.L9501 LDA &CD
       AND #&04
       BNE L9508
.L9507 RTS
;;
.L9508 JSR L92E5        ;; Print filename
       JSR LA03C        ;; Print another space
       LDY #&04
       LDA (&B6),Y      ;; Get 'E' bit
IF PATCH_INFO
       NOP
       NOP
ELSE
       BMI L9543        ;; If 'E' set, jump to finish      NOP:NOP
ENDIF
       DEY
       LDA (&B6),Y      ;; Get 'D' bit
       ROL A            ;; Rotate into Carry
       LDX #&0A         ;; X=10, Y-13 if file
       LDY #&0D
IF PATCH_INFO
       BRA L9522
ELSE
       BCC L9522        ;; Jump if file                    BRA L9522
ENDIF
       LDX #&17         ;; X=23, Y=24 if directory
       LDY #&18         ;; Just print sector start
;;
.L9522 CPX #&16
       BEQ L952B
       LDA (&B6),Y
       JSR L9322
.L952B TXA
       AND #&03
       CMP #&01
       BNE L953D
       JSR LA036        ;; Print a space
       JSR LA036        ;; Print a space
       TXA
       CLC
       ADC #&05
       TAY
.L953D DEY
       INX
       CPX #&1A
       BNE L9522
.L9543 JMP LA03A        ;; Print newline
;;
.L9546 JSR L9486
       LDY #&09
.L954B LDA ABSWS+&08CC,Y
       STA ABSWS+&0300,Y
       DEY
       BPL L954B
       LDA ABSWS+&022F
       CMP #&FF
       BNE L955E
       LDA ABSWS+&0317
.L955E STA ABSWS+&031F
       LDY #&02
.L9563 LDA ABSWS+&022C,Y
       STA ABSWS+&031C,Y
       DEY
       BPL L9563
       LDA #&FF
       STA ABSWS+&022E
       STA ABSWS+&022F
       JMP L89D8
;;
.L9577 LDA #&FF
       LDY #&00
       JSR LA97A
       LDX #&0F
.L9580 LDA L9639,X
       STA ABSWS+&0242,X
       DEX
       BPL L9580
       LDA &B4
       STA ABSWS+&0240
       LDA &B5
       STA ABSWS+&0241
       LDA #<(ABSWS+&0240)
       STA &B8
       LDA #>(ABSWS+&0240)
       STA &B9
       JSR L8DFE
       LDY #&09
       LDA ABSWS+&0237
       ORA ABSWS+&0238
       ORA ABSWS+&0239
       BEQ L95BE
.L95AB JSR L836B
       EQUB &C4         ;; ERR=196
       EQUS "Already exists"
       EQUB &00
;;
.L95BE LDA (&B4),Y
       AND #&7F
       CMP #&22
       BEQ L95CA
       CMP #&21
       BCS L95CC
.L95CA LDA #&0D
.L95CC STA (&B6),Y
       DEY
       BPL L95BE
       JSR L8F5D
       LDY #&03
.L95D6 LDA (&B6),Y
       ORA #&80
       STA (&B6),Y
       DEY
       CPY #&01
       BNE L95D6
       DEY
       LDA (&B6),Y
       ORA #&80
       STA (&B6),Y
       LDA #&00
       TAX
       TAY
.L95EC STA ABSWS+&0A00,X
       STA ABSWS+&0900,X
       STA ABSWS+&0B00,X
       STA ABSWS+&0C00,X
       STA ABSWS+&0D00,X
       INX
       BNE L95EC
       LDX #&04
.L9600 LDA L84DC,X
       STA ABSWS+&0900,X
       STA ABSWS+&0DFA,X
       LDA ABSWS+&0314,X
       STA ABSWS+&0DD6,X
       DEX
       BPL L9600
       LDX #&00
.L9614 LDA (&B4),Y
       AND #&7F
       CMP #&22
       BEQ L9620
       CMP #&21
       BCS L9622
.L9620 LDA #&0D
.L9622 STA ABSWS+&0DD9,X
       STA ABSWS+&0DCC,X
       INY
       INX
       CPX #&0A
       BNE L9614
       LDA #&0D
       STA ABSWS+&0DD9,X
       JSR L8A42
       JMP L8F8B
;;
.L9639 EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &C9
       EQUB &FF
       EQUB &FF
       EQUB &00
       EQUB &CE
       EQUB &FF
       EQUB &FF
;;
.L9649 LDA ABSWS+&022F
       CMP ABSWS+&0317
       BEQ L9654
       INC A
       BNE L966C
.L9654 LDY #&02
.L9656 LDA ABSWS+&02A2,Y
       CMP ABSWS+&022C,Y
       BNE L966C
       DEY
       BPL L9656
       LDY #&02
.L9663 LDA ABSWS+&02A8,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L9663
.L966C LDA ABSWS+&031B
       CMP ABSWS+&0317
       BNE L968C
       LDY #&02
.L9676 LDA ABSWS+&02A2,Y
       CMP ABSWS+&0318,Y
       BNE L968C
       DEY
       BPL L9676
       LDY #&02
.L9683 LDA ABSWS+&02A8,Y
       STA ABSWS+&0318,Y
       DEY
       BPL L9683
.L968C LDA ABSWS+&031F
       CMP ABSWS+&0317
       BNE L96AC
       LDY #&02
.L9696 LDA ABSWS+&02A2,Y
       CMP ABSWS+&031C,Y
       BNE L96AC
       DEY
       BPL L9696
       LDY #&02
.L96A3 LDA ABSWS+&02A8,Y
       STA ABSWS+&031C,Y
       DEY
       BPL L96A3
.L96AC LDA &CD
       AND #&08
       BNE L96B8
       JSR L8F91
       JSR LA992
.L96B8 LDA ABSWS+&02A7
       ORA ABSWS+&02A6
       ORA ABSWS+&02A5
       BNE L96C4
       RTS
;;
.L96C4 LDA ABSWS+&02A7
       ORA ABSWS+&02A6
       BNE L96D4
       LDA ABSWS+&02A5
       CMP ABSWS+&0261
       BCC L96D7
.L96D4 LDA ABSWS+&0261
.L96D7 STA ABSWS+&021E
       LDA ABSWS+&0260
       STA ABSWS+&0217
       LDX #&00
       STX ABSWS+&0216
       DEX
       STX ABSWS+&0218
       STX ABSWS+&0219
.L96EC SEC
       LDA ABSWS+&02A5
       SBC ABSWS+&0261
       STA ABSWS+&02A5
       LDA ABSWS+&02A6
       SBC #&00
       STA ABSWS+&02A6
       LDA ABSWS+&02A7
       SBC #&00
       STA ABSWS+&02A7
       BCS L9711
       LDA ABSWS+&02A5
       ADC ABSWS+&0261
       STA ABSWS+&021E
.L9711 LDA #&08
       STA ABSWS+&021A
       LDA ABSWS+&02A2
       STA ABSWS+&021D
       LDA ABSWS+&02A3
       STA ABSWS+&021C
       LDA ABSWS+&02A4
       STA ABSWS+&021B
       JSR L82AA
       LDA #&0A
       STA ABSWS+&021A
       LDA ABSWS+&02A8
       STA ABSWS+&021D
       LDA ABSWS+&02A9
       STA ABSWS+&021C
       LDA ABSWS+&02AA
       STA ABSWS+&021B
       JSR L82AA
       LDA ABSWS+&02A5
       ORA ABSWS+&02A6
       ORA ABSWS+&02A7
       BEQ L9783
       LDA ABSWS+&021E
       CMP ABSWS+&0261
       BNE L9783
       CLC
       LDA ABSWS+&02A2
       ADC ABSWS+&0261
       STA ABSWS+&02A2
       BCC L976C
       INC ABSWS+&02A3
       BNE L976C
       INC ABSWS+&02A4
.L976C CLC
       LDA ABSWS+&02A8
       ADC ABSWS+&0261
       STA ABSWS+&02A8
       BCC L9780
       INC ABSWS+&02A9
       BNE L9780
       INC ABSWS+&02AA
.L9780 JMP L96EC
;;
.L9783 LDA &CD
       AND #&08
       BEQ L978A
       RTS
;;
.L978A LDA #&C4
       STA ABSWS+&0217
       LDA #&08
       STA ABSWS+&021A
       LDA ABSWS+&0314
       STA ABSWS+&021D
       LDA ABSWS+&0315
       STA ABSWS+&021C
       LDA ABSWS+&0316
       STA ABSWS+&021B
       LDA #&05
       STA ABSWS+&021E
       JMP L82AE
;;
.L97AE LDA #&00
       STA ABSWS+&02AB
       STA ABSWS+&02AC
       STA ABSWS+&02AD
.L97B9 LDA #&FF
       STA ABSWS+&02A2
       STA ABSWS+&02A3
       STA ABSWS+&02A4
       JSR L93CC
.L97C7 LDY #&00
       LDA (&B6),Y
       BNE L97DC
       LDA ABSWS+&02A2
       AND ABSWS+&02A3
       AND ABSWS+&02A4
       INC A
       BNE L981E
       JMP L8F91
;;
.L97DC LDY #&16
       LDX #&02
       SEC
.L97E1 LDA ABSWS+&0295,Y
       SBC (&B6),Y
       INY
       DEX
       BPL L97E1
       BCS L9811
       LDY #&16
       LDX #&02
       SEC
.L97F1 LDA ABSWS+&028C,Y
       SBC (&B6),Y
       INY
       DEX
       BPL L97F1
       BCC L9811
       LDY #&16
       LDX #&02
.L9800 LDA (&B6),Y
       STA ABSWS+&028C,Y
       INY
       DEX
       BPL L9800
       LDA &B6
       STA &B4
       LDA &B7
       STA &B5
.L9811 LDA &B6
       CLC
       ADC #&1A
       STA &B6
       BCC L97C7
       INC &B7
       BCS L97C7
.L981E LDA &B4
       STA &B6
       LDA &B5
       STA &B7
       LDY #&02
.L9828 LDA ABSWS+&02A2,Y
       STA ABSWS+&02AB,Y
       DEY
       BPL L9828
       LDX #&00
       STX &B2
.L9835 CPX ABSWS+&01FE
       BCC L983D
       JMP L97B9
;;
.L983D INX
       INX
       INX
       STX &B2
       LDY #&02
.L9844 DEX
       LDA ABSWS+&0000,X
       CMP ABSWS+&02A2,Y
       BCS L9851
       LDX &B2
       BRA L9835
;;
.L9851 BNE L9856
       DEY
       BPL L9844
.L9856 LDX &B2
       CPX #&06
       BCC L986E
       LDY #&00
       CLC
       PHP
.L9860 PLP
       LDA ABSWS-6,X
       ADC ABSWS+&00FA,X
       PHP
       CMP ABSWS+&02A2,Y
       BEQ L9871
       PLP
.L986E JMP L97B9
;;
.L9871 INX
       INY
       CPY #&03
       BNE L9860
       PLP
       LDX #&02
       LDY #&12
       LDA (&B6),Y
       CMP #&01
.L9880 INY
       LDA (&B6),Y
       ADC #&00
       STA ABSWS+&0292,Y
       STA ABSWS+&022A,Y
       STA ABSWS+&0224,Y
       LDA ABSWS+&02A2,X
       STA ABSWS+&0234,X
       DEX
       BPL L9880
       JSR L84E1
       JSR L865B
       LDX #&02
       LDY #&18
.L98A1 LDA ABSWS+&023A,X
       STA (&B6),Y
       STA ABSWS+&02A8,X
       DEY
       DEX
       BPL L98A1
       JSR L9649
       JMP L97AE
;;
.L98B3 LDA #&00
       STA &C0
       STA ABSWS+&0253
       STA ABSWS+&0254
       LDA #&02
       STA ABSWS+&0252
       LDA #&CD
       STA &C1
       LDA #<L9941
       STA &B4
       LDA #>L9941
       STA &B5
.L98CE JSR L9486
       LDY #&02
.L98D3 LDA ABSWS+&0252,Y
       STA ABSWS+&08D6,Y
       DEY
       BPL L98D3
       JSR L97AE
       JSR L93CC
.L98E2 LDY #&00
       LDA (&B6),Y
       BEQ L9913
       LDY #&03
       LDA (&B6),Y
       BPL L9930
       LDA &C0
       CMP #&FE
       BEQ L9913
       LDY #&00
       LDA &B6
       STA &B4
       STA (&C0),Y
       INC &C0
       LDA &B7
       STA &B5
       STA (&C0),Y
       INC &C0
       LDX #&02
.L9908 LDA ABSWS+&0314,X
       STA ABSWS+&0252,X
       DEX
       BPL L9908
       BMI L98CE
.L9913 LDA &C0
       BEQ L993D
       LDA #<L9940
       STA &B4
       LDA #>L9940
       STA &B5
       JSR L9486
       LDY #&00
       DEC &C0
       LDA (&C0),Y
       STA &B7
       DEC &C0
       LDA (&C0),Y
       STA &B6
.L9930 CLC
       LDA &B6
       ADC #&1A
       STA &B6
       BCC L98E2
       INC &B7
       BRA L98E2
;;
.L993D JMP L89D8
;;
.L9940 EQUS "^"
.L9941 EQUB 13
;;
;; *ACCESS
;; =======
.L9942 JSR L8FE8        ;; Search for object
       BEQ L9956        ;; Jump forward if found
       JMP L8BD3        ;; Jump to 'Not found'/'Bad name'
;;
.L994A LDY #&02         ;; Clear existing LWR bits
.L994C LDA (&B6),Y
       AND #&7F
       STA (&B6),Y
       DEY
       BPL L994C
       RTS
;;
.L9956 JSR L994A        ;; Clear existing LWR bits
       LDY #&04
       LDA (&B6),Y      ;; Get existing 'E' bit
       BMI L996A        ;; Jump if 'E' file
       DEY
       LDA (&B6),Y      ;; Get 'D' bit
       AND #&80
       LDY #&00
       ORA (&B6),Y      ;; Copy 'D' bit into 'R' bit
       STA (&B6),Y      ;; Forces dirs to always have 'R'
;;
.L996A STA ABSWS+&022B  ;; Store 'E' or 'D'+'R' bit
       LDY #&00         ;; Step past filename
.L996F LDA (&B4),Y
       CMP #&20
       BCC L99C0
       BEQ L997E
       CMP #&22
       BEQ L997E
       INY
       BNE L996F
.L997E LDA (&B4),Y
       CMP #&20
       BCC L99C0
       BEQ L998A
       CMP #&22
       BNE L998D
.L998A INY
       BNE L997E
;;
.L998D LDA (&B4),Y      ;; Get access character
       AND #&DF         ;; Force to upper case
       BIT ABSWS+&022B  ;; Check 'E'/'D' flag
       BMI L99AA        ;; Jump past if already 'E' or 'D'
       CMP #&45
       BNE L99AA        ;; Jump past if not setting 'E'
       JSR L994A        ;; Clear all other bits
       LDY #&04
       LDA (&B6),Y
       ORA #&80
       STA (&B6),Y      ;; Set 'E' bit
       STA ABSWS+&022B  ;; Set 'E'/'D' flag
       BMI L99BD
;;
.L99AA LDX #&02         ;; Check if access character
.L99AC CMP L931D,X
       BEQ L99CE        ;; Matching character
       BIT ABSWS+&022B
       BMI L99B9        ;; If 'E'/'D' only check for setting 'L'
       DEX
       BPL L99AC        ;; Otherwise check all access characters
.L99B9 CMP #&21
       BCC L99C0
.L99BD INY
       BNE L998D
.L99C0 JSR L9501
       JSR L8964
       BEQ L9956
       JSR L8F91
       JMP L89D8
;;
.L99CE PHY
       TXA
       TAY
       LDA (&B6),Y
       ORA #&80
       STA (&B6),Y
       PLY
       BRA L99BD
;;
.L99DA JSR LA03A
       JSR L836B
       EQUB &92         ;; ERR=146
       EQUS "Aborted"
       EQUB &00
;;
.L99E9 LDA &B4
       PHA
       LDA &B5
       PHA
       LDA #<(ABSWS+&0240)
       STA &B8
       LDA #>(ABSWS+&0240)
       STA &B9
       JSR L94EE
       PLA
       STA &B5
       PLA
       STA &B4
       JSR L92A8
       EQUS "Destroy ?", &A0
       LDX #&03
.L9A0F JSR &FFE0
       CMP #&20
       BCC L9A19
       JSR LA03C
.L9A19 AND #&DF
       CMP L84D8,X
       BNE L99DA
       DEX
       BPL L9A0F
       JSR LA03A
       STZ ABSWS+&02D5
.L9A29 LDA &B4
       PHA
       LDA &B5
       PHA
       BIT &FF
       BPL L9A36
       JMP L82CC
;;
.L9A36 JSR L8FE8
       BNE L9A47
       JSR L9131
       PLA
       STA &B5
       PLA
       STA &B4
       JMP L9A29
;;
.L9A47 PLA
       PLA
       JMP L89D8
;;
.L9A4C JMP (&021E)
;;
;;
;; Default context
;; ===============
.L9A4F EQUS &24         ;; csd="$"
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUS &24         ;; lib="$"
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &20
       EQUB &02         ;; csd=2
       EQUB &00
       EQUB &00
       EQUB &00
       EQUB &02         ;; lib=2
.L9A68 EQUB &00
       EQUB &00
       EQUB &00
       EQUB &02         ;; back=2
;;
;;
;; Check if hard drive hardware present
;; ====================================
;; On entry: none
;; On exit:  EQ  - hard drive present
;;           NE  - no hard drive present
;;           X,Y - preserved
;;           A   - corrupted
;;
IF PATCH_SD
.L9A6C LDA #0           ;; EQ - present
       RTS
ELIF PATCH_IDE
.L9A6C LDA &FC47        ;; &FF - absent, <>&FF - present
       INC A            ;; &00 - absent, <>&00 - present
       BEQ DriveNotPresent
       LDA #0           ;; EQ - present
       RTS
.DriveNotPresent
       DEC A
       RTS
       EQUB &FC         ;; Junk - so a binary compare will pass
       STZ &FC43        ;; Junk - so a binary compare will pass
       CMP &FC40        ;; Junk - so a binary compare will pass
       RTS              ;; Junk - so a binary compare will pass
ELSE
.L9A6C LDA #&5A
       JSR L9A75
       BNE L9A7E
       LDA #&A5
.L9A75 STA &FC40
       STZ &FC43
       CMP &FC40
.L9A7E RTS
ENDIF
;;
;;
.L9A7F LDA #&A1         ;; Read CMOS
       LDX #&0B         ;; Location 11 - ADFS settings
       JSR &FFF4        ;; Read CMOS byte
       TYA              ;; Transfer CMOS byte to A
       RTS
;;
;; ADFS CMOS byte
;; --------------
;; b7    Floppy/Hard
;; b6    NoDir/Dir
;; b5    (Caps)
;; b4    (NoCaps)
;; b3    (ShCaps)
;; b2-b0 FDrive
;;
;;
.L9A88 LDA #&FD
       JSR L84C4        ;; Read BREAK type
       TXA
       RTS
;;
;; Boot command offset bytes
;; -------------------------
.L9A8F EQUB <L9A92      ;; Option 1 at L9A92
       EQUB <L9A94      ;; Option 2 at L9A94
       EQUB <L9A9C      ;; Option 3 at L9A9C
;;
;; Boot commands
;; -------------
.L9A92 EQUS "L."        ;; Start of *Load option
;;
.L9A94 EQUS "$.!BOOT"   ;; End of *Load and *Run option
       EQUB &0D
;;
.L9A9C EQUS "E.-ADFS-$.!BOOT"
                        ;; *Exec option
       EQUB &0D
;;
;;
;; SERVICE CALL HANDLERS
;; =====================
;;
;; The following tables hold addresses pushed onto the stack to call
;; service routines. Consequently, they are one byte less than the
;; actual routine addresses as the RTS opcode increments the address
;; popped from the stack
;;
;; Low service call routines address-1 low bytes
;; ---------------------------------------------
.L9AAC EQUB <(L9AD5-1)                   ;; Serv0 - L9AD5 - Null
IF ABSWS < &8000
       EQUB <(LOWABS-1)                  ;; Serv1 - L9AD5 - Low abs w/s
ELSE
       EQUB <(L9AD5-1)                   ;; Serv1 - L9AD5 - Null
ENDIF
       EQUB <(L9AFF-1)                   ;; Serv2 - L9AFF - Low priv w/s
       EQUB <(L9B54-1)                   ;; Serv3 - L9B54 - Boot FS
       EQUB <(L9D23-1)                   ;; Serv4 - L9D23 - Commands
       EQUB <(LAB89-1)                   ;; Serv5 - LAB89 - Interrupt
       EQUB <(L9AD5-1)                   ;; Serv6 - L9AD5 - Null
       EQUB <(L9AD5-1)                   ;; Serv7 - L9AD5 - Null
       EQUB <(L9D5E-1)                   ;; Serv8 - L9D5E - Osword
       EQUB <(L9E0D-1)                   ;; Serv9 - L9E0D - Help
;;
;; Low service call routines address-1 high bytes
;; ----------------------------------------------
.L9AB6 EQUB >(L9AD5-1)
IF ABSWS < &8000
       EQUB >(LOWABS-1)
ELSE
       EQUB >(L9AD5-1)
ENDIF
       EQUB >(L9AFF-1)
       EQUB >(L9B54-1)
       EQUB >(L9D23-1)
       EQUB >(LAB89-1)
       EQUB >(L9AD5-1)
       EQUB >(L9AD5-1)
       EQUB >(L9D5E-1)
       EQUB >(L9E0D-1)
;;
;; High service call routines address-1 low bytes
;; ----------------------------------------------
.L9AC0 EQUB <(L9CD9-1)                   ;; Serv21 - L9CD9 - High abs
       EQUB <(L9CE0-1)                   ;; Serv22 - L9CE0 - High w/s
       EQUB <(L9AD5-1)                   ;; Serv23 - L9AD5 - Null
       EQUB <(L9CE8-1)                   ;; Serv24 - L9CE8 - Hazel count
       EQUB <(L9CEA-1)                   ;; Serv25 - L9CEA - FS Info
       EQUB <(L9D05-1)                   ;; Serv26 - L9D05 - *SHUT
       EQUB <(L9AD5-1)                   ;; Serv27 - L9AD5 - Null
;;
;; High service call routines address-1 high bytes
;; -----------------------------------------------
.L9AC7 EQUB >(L9CD9-1)
       EQUB >(L9CE0-1)
       EQUB >(L9AD5-1)
       EQUB >(L9CE8-1)
       EQUB >(L9CEA-1)
       EQUB >(L9D05-1)
       EQUB >(L9AD5-1)
;;
;; SERVICE CALL HANDLER
;; ====================
;;
.L9ACE BIT &0DF0,X      ;; Check ROM w/s byte
       BPL L9AD6        ;; &00-&7F -> Check bit6
       BVS L9AD8        ;; &C0-&FF -> ROM enabled
;;
;; Service quit - jump here with calls not used
;; --------------------------------------------
.L9AD5 RTS              ;; &80-&BF -> ROM disabled
.L9AD6 BVS L9AD5        ;; &40-&7F -> ROM disabled
;;
;; Workspace is allowed to be at &00xx-&3Fxx or &C0xx-&FFxx. If the
;; ROM workspace byte is set to %01xxxxxx or %10xxxxxx, implying
;; workspace somewhere in &40xx-&BFxx, then the ROM is disabled.
;;
.L9AD8 CMP #&12         ;; Select filing system?
       BEQ L9B4C        ;; Jump to check FS
       CMP #&0A         ;; Service call 10 or higher?
       BCS L9AED        ;; Jump forward with higher calls
       TAX              ;; Pass service number into X
       LDA L9AB6,X      ;; Index into address table
       PHA              ;; Push service routine address
       LDA L9AAC,X      ;; onto stack
.L9AE8 PHA
       TXA              ;; Pass service number back into A
       LDX &F4          ;; Get ROM number back into X
       RTS              ;; Jump to service routine
;;
;; Service calls &21 to &27
;; ------------------------
.L9AED CMP #&21         ;; Check against the lowest value
       BCC L9AD5        ;; Quit with calls <&21
       CMP #&28
       BCS L9AD5        ;; Quit with calls >&27
       TAX              ;; Pass service call into X
       LDA L9AC7-&21,X   ;; Index into address table
       PHA              ;; Push service routine address
       LDA L9AC0-&21,X   ;; onto stack
       BRA L9AE8        ;; Jump back to jump to service routine
;;
;; Serv1 - Low absolute workspace claim
;; ====================================
IF ABSWS < &8000
.LOWABS CPY #&1C         ;; ADFS needs up to &CE00-1
        BCS labsok       ;; Exit if Y>&CE
        LDY #&1C         ;; ADFS needs up to &CE00-1
.labsok RTS
ENDIF
;;
;; Serv2 - Low workspace claim
;; ===========================
;; If insufficient workspace was available in high memory, ADFS claims
;; a page of workspace from low memory. ADFS also does some initialisation
;; on this call.
;;
.L9AFF
IF ABSWS > &8000
       LDA &0DF0,X      ;; Get workspace pointer
       CMP #&DC         ;; Is it set to <&DC00?
       BCC L9B0A        ;; Use existing value if it is
ENDIF        
       TYA
       STA &0DF0,X      ;; Use low workspace
.L9B0A PHY              ;; Save current pointer
;;
;; Now do some initialisation. Look for a hard drive?
;;
IF PATCH_PRESERVE_CONTEXT
       JSR ReadBreak
ELSE
       JSR L9A88        ;; Read BREAK type
ENDIF
       BEQ L9B3B        ;; Soft BREAK, jump ahead
       JSR LA744        ;; Find workspace
       TAY              ;; Y=0
.L9B14 LDA L9A4F,Y      ;; Initialise workspace
       CPY #&1D         ;; First 29 bytes set to dir="$",
       BCC L9B1D        ;; lib="$", csd=2, lib=2, back=2.
       LDA #&00         ;; Rest of workspace set to zero
.L9B1D STA (&BA),Y      ;; Store byte into workspace
       INY
       BNE L9B14        ;; Loop for all workspace
       JSR L9A6C        ;; Check if SCSI hardware present
       BNE L9B38        ;; Not present, jump ahead
       JSR L9A7F        ;; Read Config HARD/FLOPPY setting
       AND #&80         ;; Keep bit 7
       LDY #&17
       STA (&BA),Y      ;; Set w/s byte &17
       LDY #&1B
       STA (&BA),Y      ;; Set w/s byte &1B
       LDY #&1F
       STA (&BA),Y      ;; Set w/s byte &1F
.L9B38 JSR LA761        ;; Set workspace checksum
;;
.L9B3B JSR LA767        ;; Check workspace checksum
;;
       PLY              ;; Get pointer back
       LDX &F4          ;; Get ROM number back into X
       BIT &0DF0,X      ;; Check w/s pointer
       BMI L9B47        ;; Exit if using high workspace
       INY              ;; Claim one page of low workspace
.L9B47 LDA #&02         ;; Restore A to &02
.L9B49 RTS
;;
;;
;; Select ADFS
;; ===========
.L9B4A LDY #&08         ;; Y=8 to select ADFS
;;
;;
;; Serv12 - Select filing system
;; =============================
.L9B4C CPY #&08
       BNE L9B49        ;; No, quit
       PHY
       PHY
       BRA L9B94
;;
;;
;; Serv3 - Boot filing system
;; ==========================
.L9B54 TYA
       PHA              ;; Save Boot flag
       LDA #&7A
       JSR &FFF4        ;; Scan keyboard
       INX              ;; No key pressed?
       BEQ L9B74        ;; Yes, jump to select FS
       DEX
       CPX #&79         ;; '->' pressed?
       BEQ L9B74        ;; Yes
       CPX #&41         ;; 'A' pressed?
       BEQ L9B74        ;; Yes
       CPX #&43         ;; 'F' pressed?
       BEQ L9B72        ;; Yes, jump to select FS
       PLA
       TAY              ;; Restore Boot flag
       LDX &F4          ;; Restore ROM number
       LDA #&03         ;; Restore A=FSBoot
       RTS              ;; Return unclaimed
;;
.L9B72 PLA              ;; Replace boot flag with 'F'-Break
       PHX              ;; ...flag to prevent booting
.L9B74 CLI              ;; Enable IRQs
       PHX              ;; Save keycode
;;
;; Stack now holds:
;;   top-1: Key pressed, &FF=none, &41='A', &43='F', &79='->'
;;   top-2: Boot flag, &00=boot, <>&00=no boot
;;
       JSR L9A7F        ;; Read CMOS settings
       ASL A            ;; Move NoDir/Dir into bit7
       BPL L9B85        ;; Jump forward with NoDir
IF PATCH_PRESERVE_CONTEXT
       JSR ReadBreak
ELSE
       JSR L9A88        ;; Read BREAK type
ENDIF
       BEQ L9B85        ;; Jump forward if soft BREAK
       PLA              ;; With Hard BREAK and power on
       LDA #&43         ;; ...change key pressed to 'fadfs'
       PHA
.L9B85 JSR L92A8        ;; Print FS banner
       EQUS "Acorn ADFS", &0D, &8D
;;
;; Select ADFS
;; ===========
;; Stack now holds:
;;   top-1: Key pressed, &FF=none or *adfs, &41='A', &43='F' or *fadfs or
;;                       Serv08+Dir+Hard/PowerBreak, &79='->', &00/&08=Serv12
;;   top-2: Boot flag, &00=boot, <>&00=no boot
;;
.L9B94 LDA #&06
       JSR L9A4C        ;; Tell current FS new FS taking over
       LDA #&10
       STA ABSWS+&0200
       STZ ABSWS+&02D7
IF PATCH_SD
       STZ mmcstate%    ;; mark the mmc system as un-initialized
       JSR initializeDriveTable
ENDIF
       JSR L9A7F        ;; Get ADFS CMOS byte
       STA ABSWS+&02D8        ;; Store in workspace
       LDY #&0D         ;; Initialise vectors
.L9BA9 LDA L9CB6,Y
       STA &0212,Y
       DEY
       BPL L9BA9
       LDA #&A8
       JSR L84C4        ;; Find extended vector table
       STX &B4
       STY &B5
       LDY #&2F
       LDX #&14
.L9BBF LDA L9CC4,X      ;; Initialise extended vectors
       CMP #&FF
       BNE L9BC8
       LDA &F4
.L9BC8 STA (&B4),Y
       DEY
       DEX
       BPL L9BBF
       LDA #&8F
       LDX #&0F
       LDY #&FF
       JSR &FFF4        ;; Claim Vectors
       JSR LBA57        ;; Set a flag
       JSR LA767        ;; Check workspace checksum
       STZ ABSWS+&0208
       STZ ABSWS+&020C
       STZ ABSWS+&0210
       STZ ABSWS+&0214
       LDA #&01
       STA ABSWS+&0204
       LDY #&FB         ;; Copy workspace to &C300
.L9BF0 LDA (&BA),Y
       STA ABSWS+&0300,Y
       DEY
       BNE L9BF0        ;; Loop for 252 bytes
       LDA (&BA),Y      ;; Do zeroth byte
       STA ABSWS+&0300,Y
       LDA ABSWS+&0320  ;; Get *OPT1 setting
       AND #&04
       STA &CD          ;; Put into &CD
       JSR LA7D4        ;; Check some settings
       JSR L9A6C        ;; See if SCSI hardware present
       BNE L9C10        ;; No SCSI hardware, jump forward
       LDA #&20
       TSB &CD          ;; Signal hard drive present
.L9C10 PLA              ;; Get selection flag from stack
       CMP #&43         ;; '*fadfs'/F-Break type of selection?
       BNE L9C18        ;; No, jump to keep context
       JSR L849A        ;; Set context to &FFFFFFFF when *fadfs
.L9C18 LDY #&03         ;; Copy current context to backup context
.L9C1A LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL L9C1A
       JSR L89D8        ;; Get FSM and root from :0 if context<>-1
       LDX ABSWS+&0317  ;; Get current drive
       INX
       BEQ L9C7D        ;; No drive (eg *fadfs), jump ahead
       JSR LB4CD
IF PATCH_IDE OR PATCH_SD
       LDA ABSWS+&031B  ;; Lib not unset, jump ahead
       INC A
       BNE L9C7A
       LDA &CD          ;; If HD, look for $.Library
       AND #32
       BEQ L9C7A
       BNE L9C41
       EQUB &1B
       EQUB &C3
ELSE
       LDA ABSWS+&0318        ;; Is LIB set to ":0.$"?
       CMP #&02
       BNE L9C7A
       LDA ABSWS+&0319
       ORA ABSWS+&031A
       ORA ABSWS+&031B
ENDIF
       BNE L9C7A        ;; No, don't look for Library
.L9C41 LDA #<L9CAE
       STA &B4
       LDA #>L9CAE
       STA &B5          ;; Point to ":0.LIB*"
       JSR L8FE8
       BNE L9C7A
.L9C4E LDY #&03
       LDA (&B6),Y
       BMI L9C5B
       JSR L8964
       BNE L9C7A
       BEQ L9C4E
.L9C5B LDX #&02
       LDY #&18
.L9C5F LDA (&B6),Y
       STA ABSWS+&0318,X
       DEY
       DEX
       BPL L9C5F
       LDA ABSWS+&0317
       STA ABSWS+&031B
       LDY #&09
.L9C70 LDA (&B6),Y
       AND #&7F
       STA ABSWS+&030A,Y
       DEY
       BPL L9C70
.L9C7A JSR L89D8
.L9C7D LDA #&EA
       JSR L84C4
       LDA #&80
       TRB &CD
       INX
       BNE L9C8B
       TSB &CD
.L9C8B PLA              ;; Get boot flag
       PHA
       BNE L9CA8        ;; No boot, jump forward
       LDX ABSWS+&0317
       INX
       BNE L9C9B
       STX ABSWS+&026F
       JSR LA1A1
.L9C9B LDY ABSWS+&01FD  ;; Get boot option
       BEQ L9CA8        ;; Zero, jump to finish
       LDX L9A8F-1,Y    ;; Get
       LDY #>L9A8F
       JSR &FFF7        ;; Do *Load/*Run/*Exec
.L9CA8 LDX &F4          ;; Restore ROM number
       PLY              ;; Rebalance stack
       LDA #&00         ;; Claim the call
       RTS
;;
.L9CAE EQUS ":0.LIB*", &0D
;;
;;
;; Vector Table
;; ============
.L9CB6 EQUW &FF1B
       EQUW &FF1E
       EQUW &FF21
       EQUW &FF24
       EQUW &FF27
       EQUW &FF2A
       EQUW &FF2D
;;
;; Extended Vector Table
;; =====================
.L9CC4 EQUW L9247:EQUB &FF    ;; OSFILE
       EQUW LA97A:EQUB &FF    ;; OSARGS
       EQUW LAD72:EQUB &FF    ;; OSBGET
       EQUW LB0EC:EQUB &FF    ;; OSBPUT
       EQUW LB5CB:EQUB &FF    ;; OSGBPB
       EQUW LB213:EQUB &FF    ;; OSFIND
       EQUW L9E9D:EQUB &FF    ;; FSCV
;;
;;
;; Serv21 - Claim High Absolute Workspace
;; ======================================
.L9CD9 CPY #&CE         ;; ADFS needs up to &CE00-1
       BCS L9CDF        ;; Exit if Y>&CE
       LDY #&CE         ;; ADFS needs up to &CE00-1
.L9CDF RTS
;;
;; Serv22 - Claim High Private Workspace
;; =====================================
.L9CE0 TYA              ;; Pass w/s pointer to A
       STA &0DF0,X      ;; Store in w/s byte
       LDA #&22         ;; Restore A to &22
       INY              ;; ADFS needs one page
       RTS
;;
;; Serv24 - State how much high workspace needed
;; =============================================
.L9CE8 DEY              ;; ADFS needs one page
       RTS
;;
;; Serv25 - Return filing system information
;; =========================================
.L9CEA LDX #&0A
.L9CEC LDA L9CFA,X      ;; Copy information
       STA (&F2),Y
       INY
       DEX
       BPL L9CEC
       LDA #&25         ;; Restore A to &25
.L9CF7 LDX &F4          ;; Get ROM number back to X
       RTS
;;
;; Filing system information
;; -------------------------
.L9CFA EQUB &08         ;; Filing system number
       EQUB &39         ;; Highest handle used
       EQUB &30         ;; Lowest handle used
       EQUS "    "
.L9D01 EQUS "sfda"      ;; "adfs" filing system name
;;
;; Serv26 - *SHUT
;; ==============
.L9D05 PHY
       JSR LA744
       LDY #&AC
       LDX #&09
       LDA #&00
.L9D0F ORA (&BA),Y
       INY
       DEX
       BPL L9D0F
       TAX
       BEQ L9D1E
       JSR L9B4A
       JSR LB210
.L9D1E PLY
       LDA #&26
       BRA L9CF7
;;
;; Serv04 - *Commands
;; ==================
.L9D23 PHY              ;; Save command pointer
       LDA #&FF         ;; Flag not '*fadfs'
       PHA
       LDA (&F2),Y      ;; Get first character
       ORA #&20         ;; Force to lower case
       CMP #&66         ;; Is it 'f' of 'fadfs'?
       BNE L9D34        ;; No, jump past
       PLA              ;; Lose previos flag
       LDA #&43         ;; Change flags to indicate '*fadfs'
       PHA
       INY              ;; Point to next character
.L9D34 LDX #&03         ;; 'adfs' is 3+1 characters
.L9D36 LDA (&F2),Y      ;; Get character
       INY              ;; Move to next
       CMP #&2E         ;; Is it '.'?
       BEQ L9D47        ;; Jump to match abbreviated command
       ORA #&20         ;; Force to lower case
       CMP L9D01,X      ;; Compare with 'adfs' in FSInfo block
       BNE L9D57        ;; No match, abandon scanning
       DEX              ;; Decrease length/pointer
       BPL L9D36        ;; Loop for all four characters
.L9D47 LDA (&F2),Y      ;; Get next character
       INY              ;; Move to next character
       CMP #&20         ;; Check if it was a space
       BEQ L9D47        ;; Loop to skip spaces
       BCS L9D57        ;; Non-space found, jump to abandon
       PLX              ;; Get adfs/fadfs flag back
       PLA              ;; Get command pointer back
       PHX              ;; Add extra byte to stack
       PHX              ;; Save adfs/fadfs flag
       JMP L9B94        ;; Jump to select FS 8
;;
;; Not *fadfs/*adfs or command has extra characters after it
;; ---------------------------------------------------------
.L9D57 PLA              ;; Drop fadfs/adfs flag
       PLY              ;; Get command pointer back
       LDA #&04         ;; Restore A to '*Command'
       LDX &F4          ;; Restore ROM number
       RTS              ;; Exit
;;
;;
;; Serv8 - OSWORD calls
;; ====================
.L9D5E PHY              ;; Save Y
       LDA &EF          ;; Get OSWORD number
       CMP #&70
       BCC L9DBA        ;; If <&70, exit unclaimed
       CMP #&74
       BCS L9DBA        ;; If >&73, exit unclaimed
;;
;; The following code is VERY annoying, as it means that if you call the
;; sector access calls with another filing system selected, ADFS selects
;; itself as the current filing system, thereby trampling all over any
;; memory you may be using.
;;
       LDA #&00
       TAY
       JSR &FFDA        ;; Get current filing system
       CMP #&08         ;; Is is ADFS?
       BEQ L9D76        ;; Yes, jump to continue
       JSR L9B4A        ;; Select ADFS if ADFS not selected
.L9D76 LDA &EF          ;; Get OSWORD number
       CMP #&72         ;; Is if &72?
       BNE L9DC0        ;; No, jump ahead
;;
;;
;; OSWORD &72 - SCSI Device Access (Sector Read/Write)
;; ===================================================
       LDA &F0          ;; Copy block pointer to &BA/B
       STA &BA
       LDA &F1
       STA &BB
       LDY #&0F         ;; Copy control block to &C215
.L9D86 LDA (&BA),Y
       STA ABSWS+&0215,Y
       DEY
       BPL L9D86
;;
;; The control block is copied to ADFS filing system workspace:
;;    Addr Ctrl
;;   &C215  0  Returned result
;;   &C216  1  Addr0
;;   &C217  2  Addr1
;;   &C218  3  Addr2
;;   &C219  4  Addr3
;;   &C21A  5  Command
;;   &C21B  6  Drive+Sector b16-19
;;   &C21C  7  Sector b8-b15
;;   &C21D  8  Sector b0-b7
;;   &C21E  9  Sector Count
;;   &C21F 10  -
;;   &C220 11  Length0
;;   &C221 12  Length1
;;   &C222 13  Length2
;;   &C223 14  Length3
;;   &C224 15
;;
       LDA ABSWS+&021A        ;; Get command
       AND #&FD         ;; Mask out bit 1
       CMP #&08         ;; Is it &08 or &0A, Read or Write?
       BEQ L9DA8        ;; Jump forward with Read and Write
;;
.L9D97 LDX #<(ABSWS+&0215)
       LDY #>(ABSWS+&0215)
       INC ABSWS+&0317
       BEQ L9DA3
       DEC ABSWS+&0317
.L9DA3 JSR L80A2
       BPL L9DB0        ;; Jump to exit
;;
.L9DA8 LDA ABSWS+&021E        ;; Get Sector Count
       BNE L9D97        ;; If not zero jump back to use it
       JSR L8A4A        ;; Do the SCSI call
;;
;; Store result value and claim call
;; ---------------------------------
.L9DB0 LDY #&00         ;; Point to result byte
       STA (&BA),Y      ;; Store result in control block
.L9DB4 LDX &F4          ;; Put ROM number in X
       PLY              ;; Restore Y
       LDA #&00         ;; A=0 to claim OSWORD
       RTS
;;
;; Exit from OSWORD service call
;; -----------------------------
.L9DBA LDX &F4          ;; Put ROM number in X
       PLY              ;; Restore Y
       LDA #&08         ;; A=8 to exit with OSWORD unclaimed
       RTS
;;
;;
.L9DC0 CMP #&73
       BNE L9DD0
       LDY #&04
.L9DC6 LDA ABSWS+&02D0,Y
       STA (&F0),Y
       DEY
       BPL L9DC6
       BMI L9DB4
.L9DD0 CMP #&70
       BNE L9DE3
       LDA ABSWS+&08FA
       LDY #&00
       STA (&F0),Y
       LDA &CD
       INY
       STA (&F0),Y
       JMP L9DB4
;;
.L9DE3 CMP #&71
       BNE L9DBA
       JSR LA1EA
       LDY #&03
.L9DEC LDA ABSWS+&0215,Y
       STA (&F0),Y
       DEY
       BPL L9DEC
       BRA L9DB4
;;
.L9DF6 JSR L92A8
IF PATCH_SD
       EQUS &0D, "Advanced DFS 1.57", &8D
ELIF PATCH_IDE
       EQUS &0D, "Advanced DFS 1.53", &8D
ELSE
       EQUS &0D, "Advanced DFS 1.50", &8D
ENDIF
       RTS
.L9E0D TYA
       PHA
       LDA (&F2),Y
       CMP #&20
       BCS L9E3E
       JSR L9DF6
       JSR L92A8
       EQUS "  ADFS", &8D
.L9E22 PLA
       TAY
       LDX &F4
       LDA #&09
.L9E28 RTS
;;
.L9E29 INY
       LDA (&F2),Y
       CMP #&20
       BCS L9E28
       PLA
       PLA
       BCC L9E22
.L9E34 JSR L9E29
       BNE L9E34
.L9E39 JSR L9E29
       BEQ L9E39
.L9E3E LDX #&03
.L9E40 LDA (&F2),Y
       CMP #&2E
       BEQ L9E57
       ORA #&20
       CMP L9D01,X
       BNE L9E34
       INY
       DEX
       BPL L9E40
       LDA (&F2),Y
       CMP #&21
       BCS L9E34
.L9E57 JSR L9DF6
       LDX #&00
.L9E5C LDA L9F2D,X
       BMI L9E22
       JSR L92A8
       EQUB &20, &A0
       LDY #&09
.L9E68 LDA L9F2D,X
       BMI L9E74
       JSR LA03C
       INX
       DEY
       BPL L9E68
.L9E74 JSR LA036
       DEY
       BPL L9E74
       PHX
       LDA L9F2D+2,X
       PHA
       LSR A
       LSR A
       LSR A
       LSR A
       JSR L9283
       PLA
       AND #&0F
       JSR L9283
       JSR LA03A
       PLX
       INX
       INX
       INX
       BRA L9E5C
;;
.L9E95 EQUB <L9FFB
       EQUB <L9FB1
       EQUB <L9FBD
       EQUB <L9FC7
       EQUB <L9FD3
       EQUB <L9FDD
       EQUB <L9FE7
       EQUB <L9FF4
;;
;;
;; FSC - Filing System Control
;; ===========================
.L9E9D STX &B4          ;; Store X and Y in &B4/5
       STY &B5
       STA ABSWS+&02D6        ;; Store function
       TAX
       BMI L9EBA        ;; Function<0 - exit
       CMP #&0C
       BCS L9EBA        ;; Function>11 - exit
       STZ ABSWS+&02D5  ;; Clear
       LDA L9EC7,X      ;; Push routine address onto stack
       PHA
       LDA L9EBB,X
       PHA
       LDX &B4          ;; Retrieve X and Y
       LDY &B5
.L9EBA RTS              ;; Jump to routine
;;
;; FSC Routine Low Bytes
;; ---------------------
.L9EBB EQUB <(LA001-1)    ;;  *OPT
       EQUB <(LAD49-1)    ;;  =EOF
       EQUB <(LA3DB-1)    ;;  */
       EQUB <(L9ED3-1)    ;;  *command
       EQUB <(LA3DB-1)    ;;  *RUN
       EQUB <(L93D5-1)    ;;  *CAT
       EQUB <(LA96D-1)    ;;  NewFS taking over
       EQUB <(L9FFC-1)    ;;  File Handle Request
       EQUB <(LA0DC-1)    ;;  OSCLI being processed
       EQUB <(L943A-1)    ;;  *EX
       EQUB <(L94EE-1)    ;;  *INFO
       EQUB <(LA3DB-1)    ;;  *RUN from library
;;
;; FSC Routine High Bytes
;; ----------------------
.L9EC7 EQUB >(LA001-1)
       EQUB >(LAD49-1)
       EQUB >(LA3DB-1)
       EQUB >(L9ED3-1)
       EQUB >(LA3DB-1)
       EQUB >(L93D5-1)
       EQUB >(LA96D-1)
       EQUB >(L9FFC-1)
       EQUB >(LA0DC-1)
       EQUB >(L943A-1)
       EQUB >(L94EE-1)
       EQUB >(LA3DB-1)
;;
;; FSC 3 - *command
;; ================
.L9ED3 JSR L8328
       LDA #<(ABSWS+&02A2)
       STA &B8
       LDA #>(ABSWS+&02A2)
       STA &B9
       JSR LA50D        ;; Skip spaces, etc
       LDX #&FD         ;; Point to table start minus 3
.L9EE3 INX
       INX
       LDY #&FF         ;; Point to text line minus 1
.L9EE7 INX
       INY
       LDA L9F2D,X      ;; Get byte from command table
       BMI L9F08        ;; End of entry
       CMP (&B4),Y      ;; Compare with current character
       BEQ L9EE7        ;; Jump with match
       ORA #&20         ;; Force to lower case
       CMP (&B4),Y      ;; Compare again
       BEQ L9EE7        ;; Jump with match
       DEX
.L9EF9 INX              ;; Loop to end of entry
       LDA L9F2D,X
       BPL L9EF9
       LDA (&B4),Y      ;; Get current character
       CMP #&2E         ;; Is it a '.'?
       BNE L9EE3        ;; No, jump to check next entry
       INY              ;; Move past '.'
       BNE L9F17        ;; Jump to update line pointer
.L9F08 TYA              ;; Check line pointer
       BEQ L9F24        ;; If zero, doesn't need updating
       LDA (&B4),Y      ;; Get terminating character
       AND #&5F         ;; Force to upper case
       CMP #&41         ;; If more letters, jump to check again
       BCC L9F17
       CMP #&5B
       BCC L9EE3
.L9F17 TYA              ;; Update &B4/5 to point to params
       CLC
       ADC &B4
       STA &B4
       BCC L9F21
       INC &B5
.L9F21 JSR LA50D        ;; Skip spaces, etc.
.L9F24 LDA L9F2D,X      ;; Get command address
       PHA              ;; Stack it
       LDA L9F2D+1,X
       PHA
       RTS              ;; Jump indirectly to routine
;;
.L9F2D EQUS "ACCESS", >(L9942-1), <(L9942-1), &16
       EQUS "BACK", >(LA4D5-1), <(LA4D5-1), &00
       EQUS "BYE", >(LA103-1), <(LA103-1), &00
       EQUS "CDIR", >(L9577-1), <(L9577-1), &20
       EQUS "COMPACT", >(LA2B6-1), <(LA2B6-1), &50
       EQUS "COPY", >(LA849-1), <(LA849-1), &13
       EQUS "DESTROY", >(L99E9-1), <(L99E9-1), &10
       EQUS "DIR", >(L9546-1), <(L9546-1), &20
       EQUS "DISMOUNT", >(LA151-1), <(LA151-1), &40
       EQUS "FREE", >(LA063-1), <(LA063-1), &00
       EQUS "LCAT", >(LA4BD-1), <(LA4BD-1), &00
       EQUS "LEX", >(LA4C9-1), <(LA4C9-1), &00
       EQUS "LIB", >(LA482-1), <(LA482-1), &30
       EQUS "MAP", >(LA092-1), <(LA092-1), &00
IF PATCH_IDE OR PATCH_SD
       EQUS "MOUNT", >(MountCheck-1), <(MountCheck-1), &40
ELSE
       EQUS "MOUNT", >(LA19E-1), <(LA19E-1), &40
ENDIF
       EQUS "RENAME", >(LA541-1), <(LA541-1), &22
       EQUS "TITLE", >(LA292-1), <(LA292-1), &70
       EQUS >(LA3DB-1), <(LA3DB-1)
;;
IF PATCH_SD
       ;; The next set of strings must not straddle a page boundary
       ;; because code assumes the MSB is constant. See code at
       ;; .L9283 
       IF  ((P% AND &FF) > &B1)
               ORG ((P% + &FF) AND &FF00) 
       ENDIF
ENDIF
.L9FB1 EQUS "<List Spec>"
       EQUB &00
.L9FBD EQUS "<Ob Spec>"
       EQUB &00
.L9FC7 EQUS "<*Ob Spec*>"
       EQUB &00
.L9FD3 EQUS "(<Drive>)"
       EQUB &00
.L9FDD EQUS "<SP> <LP>"
       EQUB &00
.L9FE7 EQUS "(L)(W)(R)(E)"
       EQUB &00
.L9FF4 EQUS "<Title>"
.L9FFB EQUB &00
;;
;; FSC 7 - Handle Request
;; ======================
.L9FFC LDX #&30         ;; Lowest handle=&30
       LDY #&39         ;; Highest handle=&39
       RTS
;;
;; FSC 0 - *OPT
;; ============
.LA001 LDX &B4
       BEQ LA00F
       DEX
       BNE LA016
       LDA #&04
       TSB &CD
       TYA
       BNE LA013
.LA00F LDA #&04
       TRB &CD
.LA013 JMP L89D8
;;
.LA016 CPX #&03
       BNE LA02A
       JSR L8FF3
       JSR LB546
       LDA &B5
       AND #&03
       STA ABSWS+&01FD
       JMP L8F91
;;
.LA02A JSR L836B
       EQUB &CB         ;; ERR=203
       EQUS "Bad opt"
       EQUB &00
;;
.LA036 LDA #&20
       BRA LA03C
;;
.LA03A LDA #&0D
.LA03C PHX
       PHY
       PHA
       LDA #&C7
       LDY #&00
       JSR L84C6
       CPX #&30
       BCC LA053
       CPX #&3A
       BCS LA053
       JSR &FFF4
       LDX #&00
.LA053 PLA
       PHA
       JSR &FFE3
       LDA #&C7
       LDY #&FF
       JSR &FFF4
       PLA
       PLY
       PLX
       RTS
;;
.LA063 JSR LA1EA
       JSR LA206
       JSR L92A8
       EQUS "Free", &8D
       JSR LA1EA
       LDY #&01
       LDX #&02
       SEC
.LA079 LDA ABSWS+&00FB,Y
       SBC ABSWS+&0215,Y
       STA ABSWS+&0215,Y
       INY
       DEX
       BPL LA079
       JSR LA206
       JSR L92A8
       EQUS "Used", &8D
.LA091 RTS
.LA092 JSR L92A8
       EQUS "Address :  Length", &8D
       LDX #&00
.LA0A9 CPX ABSWS+&01FE
       BEQ LA091
       INX
       INX
       INX
       STX &C6
       LDY #&02
.LA0B5 DEX
       LDA ABSWS+&0000,X
       JSR L9322
       DEY
       BPL LA0B5
       JSR L92A8
       EQUS "  : ", &A0
       LDX &C6
       LDY #&02
.LA0CB DEX
       LDA &C100,X
       JSR L9322
       DEY
       BPL LA0CB
       JSR LA03A
       LDX &C6
       BRA LA0A9
;;
;; FSC 8 - OSCLI being processed
;; =============================
.LA0DC LDX ABSWS+&02D9
       BNE LA091        ;; Exit
       LDX ABSWS+&01FE  ;; Get FSM size
       CPX #&E1
       BCC LA091        ;; If FSM not filling up, exit
       JSR L92A8        ;; Print message
       EQUB "Compaction recommended", &8D
       RTS
;;
;;
;; *BYE
;; ====
.LA103 LDA ABSWS+&0317  ;; Get current drive
       PHA              ;; Save current drive
       TAX
       INX
       BEQ LA10E        ;; No drive selected
       JSR LB210        ;; Do CLOSE#0
.LA10E LDA #&60
       STA ABSWS+&0317  ;; Set drive to 3
.LA113 LDX #<LA12A
       LDY #>LA12A      ;; Point to control block
       JSR L80A2        ;; Do command &1B - park heads
       LDA ABSWS+&0317  ;; Get current drive
       SEC
       SBC #&20         ;; Step back one
       STA ABSWS+&0317
       BCS LA113        ;; Loop for drives 3 to 0
       PLA
       STA ABSWS+&0317  ;; Restore current drive
       RTS
;;
.LA12A EQUB &00
       EQUB <(ABSWS+&0900) ;; ;; &FFFFC900
       EQUB >(ABSWS+&0900)
       EQUB &FF
       EQUB &FF
       EQUB &1B         ;; ;; Command &1B
       EQUB &00         ;; ;; Drive 0, Sector 0
       EQUB &00
       EQUB &00
       EQUB &00         ;; ;; Zero sector
       EQUB &00
;;
.LA135 JSR LA50D
       LDY ABSWS+&0317
       INY
       BEQ LA13F
       DEY
.LA13F STY ABSWS+&026F
       LDY #&00
       LDA (&B4),Y
       CMP #&20
       BCC LA150
       JSR L8847
       STA ABSWS+&026F   ;; Set drive number
.LA150 RTS
;;
.LA151 JSR LA135
       LDX #&09
.LA156 LDA ABSWS+&03AC,X
       BEQ LA16F
       LDA ABSWS+&03B6,X
       AND #&E0
       CMP ABSWS+&026F
       BNE LA16F
       CLC
       TXA
       ADC #&30
       TAY
       LDA #&00
       JSR LB213
.LA16F DEX
       BPL LA156
       LDA ABSWS+&0317
       CMP ABSWS+&026F
       BNE LA1B9
       LDA #&FF
       STA ABSWS+&0317
       STA ABSWS+&0316
       LDX #&00
       JSR LA189
       BRA LA1B9
;;
.LA189 LDY #&09
.LA18B LDA LA196-2,Y
       STA ABSWS+&0300,X
       INX
       DEY
       BPL LA18B
       RTS
;;
.LA196 EQUS &0D, &22, "tesnU", &22
;;
;; *MOUNT
;; ======
.LA19E JSR LA135        ;; Scan drive number parameter
.LA1A1 LDA ABSWS+&026F  ;; Get drive
       STA ABSWS+&0317  ;; Set current drive
       LDX #<LA1DF
       LDY #>LA1DF
       JSR L80A2        ;; Do SCSI command &1B - Park
       LDA #<(LA2EB-1)
       STA &B4
       LDA #>(LA2EB-1)
       STA &B5          ;; Point to LA2EA
       JSR L9546        ;; Do something
.LA1B9 LDA ABSWS+&031F  ;; Get previous drive
       CMP ABSWS+&026F  ;; Compare with ???
       BNE LA1C9        ;; If different, jump past
       LDA #&FF
       STA ABSWS+&031E  ;; Set previous directory to &FFFFxxxx
       STA ABSWS+&031F
.LA1C9 LDA ABSWS+&031B  ;; Get library drive
       CMP ABSWS+&026F  ;; Compare with ???
       BNE LA1DE        ;; If different, jump past
       LDA #&FF
       STA ABSWS+&031A  ;; Set library to &FFFFxxxx
       STA ABSWS+&031B
       LDX #&0A
       JSR LA189        ;; Set library name to "Unset"
.LA1DE RTS
;;
.LA1DF EQUB &00         ;; ;; Flag = &00
       EQUB <(ABSWS+&0900) ;; ;; &FFFFC900
       EQUB >(ABSWS+&0900)
       EQUB &FF
       EQUB &FF
       EQUB &1B         ;; ;; Command &1B - Park
       EQUB &00         ;; ;; Drive 0, Sector 0
       EQUB &00
       EQUB &00
       EQUB &01         ;; ;; 1 sector
       EQUB &00
;;
.LA1EA LDA #&00
       LDX #&03
.LA1EE STA ABSWS+&0215,X
       STA ABSWS+&0227,X
       DEX
       BPL LA1EE
       JSR L8632
       LDX #&02
.LA1FC LDA ABSWS+&025D,X
       STA ABSWS+&0216,X
       DEX
       BPL LA1FC
       RTS
;;
.LA206 LDA ABSWS+&0218
       JSR L9322
       LDA ABSWS+&0217
       JSR L9322
       LDA ABSWS+&0216
       JSR L9322
       JSR L92A8
       EQUS " Sectors =", &A0
       LDX #&1F
       STX ABSWS+&0233
       LDA #&00
       LDX #&09
.LA22F STA ABSWS+&0240,X
       DEX
       BPL LA22F
.LA235 ASL ABSWS+&0215
       ROL ABSWS+&0216
       ROL ABSWS+&0217
       ROL ABSWS+&0218
       LDX #&00
       LDY #&09
.LA245 LDA ABSWS+&0240,X
       ROL A
       CMP #&0A
       BCC LA24F
       SBC #&0A
.LA24F STA ABSWS+&0240,X
       INX
       DEY
       BPL LA245
       DEC ABSWS+&0233
       BPL LA235
       LDY #&20
       LDX #&08
.LA25F BNE LA263
       LDY #&2C
.LA263 LDA ABSWS+&0240,X
       BNE LA270
       CPY #&2C
       BEQ LA270
       LDA #&20
       BNE LA275
.LA270 LDY #&2C
       CLC
       ADC #&30
.LA275 JSR LA03C
       CPX #&06
       BEQ LA280
       CPX #&03
       BNE LA284
.LA280 TYA
       JSR LA03C
.LA284 DEX
       BPL LA25F
       JSR L92A8
       EQUS " Bytes",&A0
       RTS
.LA292 JSR LB546
       JSR L8FF3
       JSR LA50D
       LDY #&00
.LA29D LDA (&B4),Y
       AND #&7F
       CMP #&22
       BEQ LA2A9
       CMP #&20
       BCS LA2AB
.LA2A9 LDA #&0D
.LA2AB STA ABSWS+&08D9,Y
       INY
       CPY #&13
       BNE LA29D
       JMP L8F91
;;
.LA2B6 JSR LA50D
       LDY #&00
       LDA (&B4),Y
       CMP #&21
       BCS LA2EB
       LDA #&84
       JSR &FFF4
       TXA
       BNE LA2DB
       TYA
       BMI LA2DB
       STA ABSWS+&0260
       LDA #&80
       SEC
       SBC ABSWS+&0260
       STA ABSWS+&0261
       JMP LA377
;;
.LA2DB JSR L836B
       EQUB &94         ;; ERR=148
       EQUS "Bad compact"
       EQUB &00
;;
.LA2EB STA ABSWS+&0215
       INY
       LDA (&B4),Y
       STA ABSWS+&0216
       INY
       LDA (&B4),Y
       CMP #&20
       BEQ LA2FF
       CMP #&2C
       BNE LA2DB
.LA2FF INY
       LDA (&B4),Y
       CMP #&20
       BEQ LA2FF
       STA ABSWS+&0217
       INY
       LDA (&B4),Y
       STA ABSWS+&0218
       CMP #&21
       BCS LA31F
       LDA ABSWS+&0217
       STA ABSWS+&0218
       LDA #&30
       STA ABSWS+&0217
       DEY
.LA31F INY
       LDA (&B4),Y
       CMP #&20
       BEQ LA31F
       BCS LA2DB
       LDX #&03
.LA32A LDA ABSWS+&0215,X
       CMP #&30
       BCC LA2DB
       CMP #&3A
       BCS LA33D
       SEC
       SBC #&30
       STA ABSWS+&0215,X
       BPL LA34C
.LA33D AND #&5F
       CMP #&41
       BCC LA2DB
       CMP #&47
       BCS LA2DB
       SBC #&36
       STA ABSWS+&0215,X
.LA34C DEX
       BPL LA32A
       INX
       JSR LA389
       BMI LA2DB
       STA ABSWS+&0260
       LDX #&02
       JSR LA389
       BPL LA362
.LA35F JMP LA2DB
;;
.LA362 BEQ LA35F
       STA ABSWS+&0261
       CLC
       LDA ABSWS+&0260
       ADC ABSWS+&0261
       BPL LA377
       CMP #&80
       BEQ LA377
       JMP LA2DB
;;
.LA377 JSR LB210
       JSR L8328
       LDA #&08
       TSB &CD
       JSR L98B3
       LDA #&08
       TRB &CD
       RTS
;;
.LA389 LDA ABSWS+&0215,X
       ASL A
       ASL A
       ASL A
       ASL A
       ORA ABSWS+&0216,X
       RTS
;;
.LA394 JSR LA4F5
       LDA &B5
       PHA
       LDA &B4
       PHA
       JSR LA4F5
       LDY #&00
       LDA (&B4),Y
       CMP #&20
       BCS LA3CB
       PLA
       STA &B4
       STA ABSWS+&0240
       PLA
       STA &B5
       STA ABSWS+&0241
       RTS
;;
.LA3B5 JSR LA4B1
       JSR L89D8
       LDA ABSWS+&02D6  ;; Get FSC function
       CMP #&0B         ;; Was this Run from libfs?
       BEQ LA3CB        ;; Yes, jump to error
       LDA #&0B         ;; Otherwise, pass on to libfs
       LDX &C0
       LDY &C1
       JMP L9A4C        ;; Pass on to FSC to call libfs
;;
.LA3CB JSR L836B        ;; Generate error
       EQUB &FE         ;; ERR=254
       EQUS "Bad command"
       EQUB &00
;;
;; FSC 2,4,11 - */, *RUN, *RUN from library
;; ========================================
.LA3DB LDA &B4
       STA &C0
       LDA &B5
       STA &C1
       JSR L8BBE
       BEQ LA3FE
       JSR L89D8
       LDA &C0
       STA &B4
       LDA &C1
       STA &B5
       JSR LA49E
       JSR L8BBE
       BNE LA3B5
       JSR LA4B1
.LA3FE LDA &B4
       STA ABSWS+&02A2
       LDA &B5
       STA ABSWS+&02A3
       LDY #&0E
       LDA (&B6),Y
       LDX #&02
.LA40E INY
       AND (&B6),Y
       DEX
       BPL LA40E
       INC A
       BNE LA42A
       LDX &B6
       LDY &B7
       LDA #&40
       JSR LB213
       STA ABSWS+&0332
       LDX #<L9A9C         ;; Point to E.-ADFS-$.!BOOT
       LDY #>L9A9C
       JMP &FFF7
;;
.LA42A LDY #&0B
       LDA (&B6),Y
       INY
       AND (&B6),Y
       INY
       AND (&B6),Y
       INC A
       BNE LA43F
       JSR L836B
       EQUB &93         ;; ERR=147
       EQUS "No!"
       EQUB &00
;;
.LA43F LDA #&A5
       STA ABSWS+&02A8
       LDX #<(ABSWS+&02A2)
       LDY #>(ABSWS+&02A2)
       STX &B8
       STY &B9
       JSR L8BBE
       LDY #&04
       LDA (&B6),Y
       LDY #&00
       ORA (&B6),Y
       BMI LA45C
       JMP L8BFB
;;
.LA45C JSR L8C1B
       LDA ABSWS+&02AB
       CMP #&FF
       BNE LA472
       LDA ABSWS+&02AA
       CMP #&FE
       BCC LA472
.LA46D LDA #&01
       JMP (ABSWS+&02A8)
;;
.LA472 BIT &CD
       BPL LA46D
       JSR L8032
       LDX #<(ABSWS+&02A8)
       LDY #>(ABSWS+&02A8)
       LDA #&04
       JMP &0406
;;
.LA482 JSR L9486
       LDY #&09
.LA487 LDA ABSWS+&08CC,Y
       STA ABSWS+&030A,Y
       DEY
       BPL LA487
       LDY #&03
.LA492 LDA ABSWS+&0314,Y
       STA ABSWS+&0318,Y
       DEY
       BPL LA492
.LA49B JMP L89D8
;;
.LA49E LDY #&03
.LA4A0 LDA ABSWS+&0314,Y
       STA ABSWS+&0230,Y
       LDA ABSWS+&0318,Y
       STA ABSWS+&022C,Y
       DEY
       BPL LA4A0
       BMI LA49B
.LA4B1 LDY #&03
.LA4B3 LDA ABSWS+&0230,Y
       STA ABSWS+&022C,Y
       DEY
       BPL LA4B3
       RTS
;;
.LA4BD JSR LA49E
       JSR LA4B1
       JSR L93DB
       JMP L89D8
;;
.LA4C9 JSR LA49E
       JSR LA4B1
       JSR L943D
       JMP L89D8
;;
.LA4D5 LDY #&03
.LA4D7 LDA ABSWS+&031C,Y
       STA ABSWS+&022C,Y
       LDA ABSWS+&0314,Y
       STA ABSWS+&031C,Y
       DEY
       BPL LA4D7
       JSR L89D8
       LDY #&09
.LA4EB LDA ABSWS+&08CC,Y
       STA ABSWS+&0300,Y
       DEY
       BPL LA4EB
       RTS
;;
.LA4F5 LDY #&00
.LA4F7 JSR L8743
       BEQ LA4FF
.LA4FC INY
       BNE LA4F7
.LA4FF CMP #&2E
       BEQ LA4FC
       TYA
       CLC
       ADC &B4
       STA &B4
       BCC LA50D
       INC &B5
;;
.LA50D LDY #&00
       CLC
       PHP
.LA511 LDA (&B4),Y      ;; Get current character
       CMP #&20         ;; Is it a space?
       BCC LA528        ;; Control character,
       BEQ LA525        ;; Space,
       CMP #&22         ;; Is it a quote?
       BNE LA528
       PLP
       BCC LA523
       JMP L8760
;;
.LA523 SEC
       PHP
.LA525 INY
       BNE LA511
.LA528 TYA
       PLP
       CLC
       ADC &B4
       STA &B4
       BCC LA533
       INC &B5
.LA533 RTS
;;
.LA534 LDY #&00
       LDA (&B4),Y
       AND #&7F
       CMP #&3A
       BNE LA533
.LA53E JMP L8988
;;
.LA541 LDA &B4
       PHA
       LDA &B5
       PHA
       JSR LA534
       JSR L8DC8
       JSR L8BF0
       BEQ LA555
       JMP L8BD3
;;
.LA555 LDY #&03
       LDA (&B6),Y
       JSR L89D8
       BPL LA580
       PLX
       PLA
       STA &B4
       STX &B5
       PHA
       PHX
       LDY #&00
       LDA (&B4),Y
       AND #&7D
       CMP #&24
       BEQ LA53E
.LA570 JSR L8743
       BEQ LA57C
       CMP #&5E
       BEQ LA53E
.LA579 INY
       BNE LA570
.LA57C CMP #&2E
       BEQ LA579
.LA580 JSR LA394
       JSR LA534
       LDA #<(ABSWS+&0240)
       STA &B8
       LDA #>(ABSWS+&0240)
       STA &B9
       JSR L8CED
       PHP
       JSR L8E01
       PLP
       BNE LA5A5
       LDA &B6
       LDY #&03
.LA59C STA ABSWS+&0234,Y
       LDA ABSWS+&0313,Y
       DEY
       BPL LA59C
.LA5A5 LDA ABSWS+&022E
       BPL LA5B5
       LDY #&02
.LA5AC LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL LA5AC
.LA5B5 JSR L89D8
       PLX
       PLA
       STA &B4
       STX &B5
       PHA
       PHX
       JSR L8FE8
       JSR L8D1B
       LDY #&03
       LDA &B6
.LA5CA CMP ABSWS+&0234,Y
       BNE LA625
       LDA ABSWS+&0313,Y
       DEY
       BPL LA5CA
       PLA
       STA &B5
       PLA
       STA &B4
       JSR LA394
.LA5DE LDY #&00
.LA5E0 LDA (&B4),Y
       CMP #&2E
       BEQ LA5EF
       AND #&7D
       CMP #&21
       BCC LA5FA
       INY
       BRA LA5E0
;;
.LA5EF TYA
       ADC &B4
       STA &B4
       BCC LA5DE
       INC &B5
       BNE LA5DE
.LA5FA LDY #&09
.LA5FC LDA (&B6),Y
       AND #&80
       STA ABSWS+&022B
       LDA (&B4),Y
       AND #&7F
       CMP #&22
       BEQ LA60F
       CMP #&21
       BCS LA611
.LA60F LDA #&0D
.LA611 ORA ABSWS+&022B
       STA (&B6),Y
       DEY
       BPL LA5FC
       JSR L8F91
       JSR LA6BB
       JMP L89D8
;;
.LA622 JMP L95AB
;;
.LA625 LDA ABSWS+&0237
       BNE LA622
       LDY #&09
       LDA (&B6),Y
       ORA #&80
       STA (&B6),Y
       JSR L8F91
       LDY #&0A
       LDX #&07
.LA639 LDA (&B6),Y
       STA ABSWS+&0238,Y
       INY
       DEX
       BPL LA639
       STZ ABSWS+&024A
       STZ ABSWS+&024B
       STZ ABSWS+&024C
       STZ ABSWS+&024D
       LDX #&03
.LA650 LDA (&B6),Y
       STA ABSWS+&023C,Y
       INY
       DEX
       BPL LA650
       LDY #&00
.LA65B LDA (&B6),Y
       ROL A
       ROL ABSWS+&025D
       INY
       CPY #&04
       BNE LA65B
       JSR LA394
       LDY #&18
       LDX #&02
.LA66D LDA (&B6),Y
       STA ABSWS+&023A,X
       DEY
       DEX
       BPL LA66D
       JSR L89D8
       LDA #<(ABSWS+&0240)
       STA &B8
       LDA #>(ABSWS+&0240)
       STA &B9
       JSR L8DFE
       JSR L8E7A
       LDY #&03
.LA689 LDA (&B6),Y
       ASL A
       ROR ABSWS+&025D
       ROR A
       STA (&B6),Y
       DEY
       BPL LA689
       JSR L8E96
       JSR L8F63
       JSR L8F91
       JSR LA6BB
       JSR L89D8
       PLA
       STA &B5
       PLA
       STA &B4
       JSR L8FE8
       LDX #&05
.LA6AF STZ ABSWS+&0234,X
       DEX
       BPL LA6AF
       JSR L921B
       JMP L89D8
;;
.LA6BB LDY #&03
       LDA (&B6),Y
       BMI LA6C2
       RTS
;;
.LA6C2 LDY #&02
.LA6C4 LDA ABSWS+&0314,Y
       STA ABSWS+&0270,Y
       DEY
       BPL LA6C4
       LDY #&09
.LA6CF LDA (&B6),Y
       AND #&7F
       STA ABSWS+&0274,Y
       DEY
       BPL LA6CF
       LDA #<(ABSWS+&0274)
       STA &B4
       LDA #>(ABSWS+&0274)
       STA &B5
       JSR L9486
       LDY #&09
.LA6E6 LDA ABSWS+&0274,Y
       STA ABSWS+&08CC,Y
       DEY
       BPL LA6E6
       LDY #&02
.LA6F1 LDA ABSWS+&0270,Y
       STA ABSWS+&08D6,Y
       DEY
       BPL LA6F1
       JMP L8F91
;;
;; Check loaded directory
;; ----------------------
.LA6FD LDX ABSWS+&0317  ;; Get current drive
       INX              ;; If &FF, no directory loaded
       BNE LA72E        ;; Directory loaded, exit
       JSR L8372        ;; Generate error
       EQUB &A9         ;; ERR=169
       EQUS "No directory"
       EQUB &00
;;
.LA714 JSR LA6FD        ;; Check if directory loaded
       LDX #&00         ;; Point to first character to check
       LDA ABSWS+&08FA  ;; Get initial character
.LA71C CMP ABSWS+&0400,X ;; Check "Hugo" string at start of dir
       BNE LA72F        ;; Jump to give broken dir error
       CMP ABSWS+&08FA,X ;; Check "Hugo" string at end of dir
       BNE LA72F        ;; Jump to give broken dir error
       INX              ;; Move to next char
       LDA L84DC,X      ;; Get byte from "Hugo" string
       CPX #&05
       BNE LA71C        ;; Loop for 4 characters
.LA72E RTS
;;
.LA72F JSR L834E        ;; Generate error
       EQUB &A8         ;; ERR=168
       EQUS "Broken directory"
       EQUB &00
;;
;; Get pointer to workspace into &BA/B
;; ===================================
.LA744 LDX &F4
       LDA &0DF0,X
       STA &BB
       LDA #&00
       STA &BA
       RTS
;;
;;
;; Calculate workspace checksum
;; ----------------------------
.LA750 JSR LA744        ;; Find workspace
       LDY #&FD
       TYA
       CLC
.LA757 ADC (&BA),Y      ;; Add up contents of workspace
       DEY
       BNE LA757        ;; Loop for 252 bytes
       ADC (&BA),Y      ;; Add zeroth byte
       LDY #&FE         ;; Point to checksum
       RTS
;;
;; Set workspace checksum
;; ----------------------
.LA761 JSR LA750        ;; Calculate workspace checksum
       STA (&BA),Y      ;; Store checksum
.LA766 RTS
;;
;; Check workspace checksum
;; ------------------------
.LA767 JSR LA750        ;; Calculate workspace checksum
       CMP (&BA),Y      ;; Does it match?
       BEQ LA766        ;; Exit if it does
.LA76E LDA #&0F
       STA ABSWS+&02CE
       JSR L8372        ;; Generate error
       EQUB &AA         ;; ERR=170
       EQUS "Bad sum"
       EQUB &00
;;
.LA77F PHP              ;; Save all registers
       PHA
       PHY
       PHX
       LDA ABSWS+&02CE        ;; Get workspace checksum
       BNE LA76E        ;; If nonzero, generate 'Bad sum' error
       JSR L8FF3        ;; Check FSM checksum
       CLC
       LDX #&10
.LA78E LDA ABSWS+&0204,X
       AND #&21
       BEQ LA79B
       BCS LA76E
       CMP #&01
       BNE LA76E
.LA79B DEX
       DEX
       DEX
       DEX
       BPL LA78E
       BCC LA76E
       JSR LA7C9
       CMP ABSWS+&02C1
       BNE LA76E
       PHA              ;; Create two spaces on stack
       PHA
       LDY #&05         ;; Move stack down two bytes
       TSX
.LA7B0 LDA &0103,X
       STA &0101,X
       INX
       DEY
       BPL LA7B0
       LDA #<(LA7D4-1)
       STA &0101,X
       LDA #>(LA7D4-1)
       STA &0102,X      ;; Force return address to LA7D4
       PLX
       PLY
       PLA
       PLP
       RTS
;;
.LA7C9 LDX #&78
       TXA
       CLC
.LA7CD ADC ABSWS+&0383,X
       DEX
       BNE LA7CD
       RTS
;;
.LA7D4 PHP              ;; Save all registers
       PHA
       PHY
       PHX
       JSR LA7C9
       STA ABSWS+&02C1
       STZ ABSWS+&02CE
       STZ ABSWS+&02D5
       STZ ABSWS+&02D9
       PLX
       PLY
       PLA
       PLP
       RTS
;;
.LA7EC LDA ABSWS+&0291
       STA &B4
       LDA ABSWS+&0292
       STA &B5
       LDA ABSWS+&0294
       STA &B7
       LDA ABSWS+&0293
       STA &B6
       LDX #&0B
.LA802 LDA L883B,X
       STA ABSWS+&0214,X
       DEX
       BNE LA802
       LDY #&03
.LA80D LDA ABSWS+&026C,Y
       STA ABSWS+&0314,Y
       CPX #&00
       BEQ LA81A
       STA ABSWS+&021A,X
.LA81A INX
       DEY
       BPL LA80D
       JMP L82AA
;;
.LA821 LDX #&0B
.LA823 LDA L883B,X
       STA ABSWS+&0214,X
       DEX
       BNE LA823
       LDY #&03
.LA82E LDA ABSWS+&0270,Y
       STA ABSWS+&0314,Y
       CPX #&00
       BEQ LA83B
       STA ABSWS+&021A,X
.LA83B INX
       DEY
       BPL LA82E
       JSR L82AA
       LDX #<L8831
       LDY #>L8831
       JMP L82AE
;;
.LA849 LDA #<(ABSWS+&027F)
       STA &B8
       LDA #>(ABSWS+&027F)
       STA &B9
       LDA #<(ABSWS+&0274)
       STA &C27F
       LDA #>(ABSWS+&0274)
       STA ABSWS+&0280
       JSR L8BBE
       BEQ LA863
       JMP L8BD3
;;
.LA863 LDA &B6
       STA ABSWS+&0293
       LDA &B7
       STA ABSWS+&0294
       LDA &B4
       STA ABSWS+&0291
       LDA &B5
       STA ABSWS+&0292
       LDY #&03
.LA879 LDA ABSWS+&0314,Y
       STA ABSWS+&026C,Y
       DEY
       BPL LA879
       JSR L89D8
       LDY #&03
.LA887 LDA ABSWS+&0314,Y
       STA ABSWS+&022C,Y
       DEY
       BPL LA887
       JSR LA394
       JSR L8743
       BNE LA89B
       JMP L8760
;;
.LA89B JSR L9486
       JSR L8FF3
       LDY #&03
.LA8A3 LDA ABSWS+&0314,Y
       STA ABSWS+&0270,Y
       DEY
       BPL LA8A3
       JSR LA7EC
.LA8AF LDY #&04
       LDA (&B6),Y
       DEY
       ORA (&B6),Y
       BPL LA8C7
.LA8B8 BIT &FF
       BPL LA8BF
       JMP L82CC
;;
.LA8BF JSR L8964
       BEQ LA8AF
       JMP L89D8
;;
.LA8C7 LDA &B6
       STA ABSWS+&0293
       LDA &B7
       STA ABSWS+&0294
       JSR L8C6D
       LDY #&16
       LDA (&B6),Y
       STA ABSWS+&02A2
       INY
       LDA (&B6),Y
       STA ABSWS+&02A3
       INY
       LDA (&B6),Y
       ORA ABSWS+&0317
       STA ABSWS+&02A4
       LDX #&00
       LDY #&03
.LA8EE LDA ABSWS+&0289,Y
       STA ABSWS+&028D,Y
       TXA
       STA ABSWS+&0289,Y
       DEY
       BPL LA8EE
       LDY #&09
.LA8FD LDA (&B6),Y
       AND #&7F
       STA ABSWS+&0274,Y
       DEY
       BPL LA8FD
       LDA #&0D
       STA ABSWS+&027E
       JSR LA821
       JSR L8DFE
       JSR L8E7A
       JSR L8F5D
       LDY #&02
.LA91A LDA ABSWS+&023A,Y
       STA ABSWS+&02A8,Y
       LDA ABSWS+&023D,Y
       STA ABSWS+&02A5,Y
       DEY
       BPL LA91A
       LDA #&83
       JSR &FFF4
       STY ABSWS+&0260
       LDA #&84
       JSR &FFF4
       TYA
       SEC
       SBC ABSWS+&0260
       STA ABSWS+&0261
       LDA #&08
       TSB &CD
       LDA ABSWS+&026F
       ORA ABSWS+&02A4
       STA ABSWS+&02A4
       LDA ABSWS+&0273
       ORA ABSWS+&02AA
       STA ABSWS+&02AA
       LDA ABSWS+&0317
       PHA
       LDA #&00
       STA ABSWS+&0317
       JSR L96AC
       PLA
       STA ABSWS+&0317
       JSR L8F91
       JSR LA7EC
       JMP LA8B8
;;
;; FSC 6 - New FS taking over
;; ==========================
.LA96D LDX ABSWS+&0317
       INX
       BEQ LA983
       JSR L89D8
       LDA #&FF         ;; Continue into OSARGS &FF,0
       LDY #&00         ;;  to ensure all files
;;
;; OSARGS
;; ======
.LA97A CPY #&00
       BNE LA9A8        ;; Jump with OSARGS Y<>0, info on channel
       TAY
       BNE LA984        ;; Jump with OSARGS Y=0, info on filing system
       LDA #&08         ;; OSARGS 0,0 - return filing system number
.LA983 RTS
;;
;; OSARGS Y=0 - Info on filing system
;; ----------------------------------
.LA984 JSR LA77F        ;; Check FSM
       STX &C3          ;; Store X, pointer to data word in zero page
       DEY              ;; Y=&FF
       BNE LA992        ;; Jump forward
;;
;; Exit OSARGS Y=0
;; ---------------
.LA98C LDX &C3          ;; Restore X
       LDA #&00         ;; A=0
       TAY              ;; Y=0
       RTS
;;
;; OSARGS Y=0 - implement all calls as ENSURE (A=&FF)
;; --------------------------------------------------
.LA992 LDX #&10
.LA994 JSR LAB06        ;; Check things
       STZ ABSWS+&0204,X
       DEX
       DEX
       DEX
       DEX
       BPL LA994
       INC ABSWS+&0204
       JSR L8328        ;; Wait for ensuring to complete
       BRA LA98C        ;; Exit
;;
;; OSARGS Y<>0 - Info on open channel
;; ----------------------------------
.LA9A8 JSR LA77F        ;; Check FSM
.LA9AB STX &C3          ;; Store X, pointer to data word in zero page
       PHA
       JSR LAD0D        ;; Check channel and channel flags
       JSR LB1E9
       PLA              ;; Get action back
       LDY &CF          ;; Y=offset to channel info
       TAX
       BNE LA9DA        ;; Jump if not 0, not =PTR
;;
;; OSARGS 0,Y - Read PTR
;; ---------------------
       LDX &C3          ;; Get pointer to data word
       LDA ABSWS+&037A,Y ;; Copy PTR to data word
       STA &00,X
       LDA ABSWS+&0370,Y
       STA &01,X
       LDA ABSWS+&0366,Y
       STA &02,X
       LDA ABSWS+&035C,Y
       STA &03,X
.LA9D0 JSR LB19C
       LDA #&00         ;; A=0 - action done
       LDX &C3          ;; Restore X,Y
       LDY &C2
       RTS
;;
;; OSARGS 1,Y - Write PTR
;; ----------------------
.LA9DA DEX
       BNE LAA59        ;; Jump if not 1, not PTR=
       LDA ABSWS+&03AC,Y
       BPL LAA16
.LA9E2 LDX &C3
       LDA &00,X
       STA ABSWS+&029A
       LDA &01,X
       STA ABSWS+&029B
       LDA &02,X
       STA ABSWS+&029C
       LDA &03,X
       STA ABSWS+&029D
       JSR LAE68
       LDX &C3
       LDY &CF
       LDA &00,X
       STA ABSWS+&037A,Y
       LDA &01,X
       STA ABSWS+&0370,Y
       LDA &02,X
       STA ABSWS+&0366,Y
       LDA &03,X
       STA ABSWS+&035C,Y
       JMP LA9D0
;;
.LAA16 LDX &C3
       LDY &CF
       SEC
       LDA ABSWS+&0352,Y
       SBC &00,X
       LDA ABSWS+&0348,Y
       SBC &01,X
       LDA ABSWS+&033E,Y
       SBC &02,X
       LDA ABSWS+&0334,Y
       SBC &03,X
       BCC LAA48
       LDA &00,X
       STA ABSWS+&037A,Y
       LDA &01,X
       STA ABSWS+&0370,Y
       LDA &02,X
       STA ABSWS+&0366,Y
       LDA &03,X
       STA ABSWS+&035C,Y
       JMP LA9D0
;;
.LAA48 JSR L836B
       EQUB &B7         ;; ERR=183
       EQUS "Outside file"
       EQUB &00
;;
;; OSARGS 2,Y - Read EXT
;; ---------------------
.LAA59 DEX
       BNE LAA75
       LDX &C3
       LDA ABSWS+&0352,Y
       STA &00,X
       LDA ABSWS+&0348,Y
       STA &01,X
       LDA ABSWS+&033E,Y
       STA &02,X
       LDA ABSWS+&0334,Y
       STA &03,X
.LAA72 JMP LA9D0
;;
;; OSARGS 3,Y - Write EXT
;; ----------------------
.LAA75 DEX
       BNE LAAB9
       LDX &C3
       LDA ABSWS+&03AC,Y
       BMI LAA82
       JMP LB0FA
;;
.LAA82 LDA &00,X
       STA ABSWS+&029A
       LDA &01,X
       STA ABSWS+&029B
       LDA &02,X
       STA ABSWS+&029C
       LDA &03,X
       STA ABSWS+&029D
       JSR LAE68
       LDX &C3
       LDY &CF
       LDA &00,X
       STA ABSWS+&0352,Y
       LDA &01,X
       STA ABSWS+&0348,Y
       LDA &02,X
       STA ABSWS+&033E,Y
       LDA &03,X
       STA ABSWS+&0334,Y
       JSR LAD25
       BCS LAA72
       JMP LA9E2
;;
;; OSARGS 4+,Y - treat as OSARGS &FF,Y - Ensure File
;; -------------------------------------------------
.LAAB9 LDX #&10
.LAABB LDA ABSWS+&0204,X
       LSR A
       AND #&0F
       CMP &CF
       BNE LAAD0
       JSR LAB06
       LDA ABSWS+&0204,X
       AND #&01
       STA ABSWS+&0204,X
.LAAD0 DEX
       DEX
       DEX
       DEX
       BPL LAABB
       JMP LA98C
;;
;; Send a command block to SCSI for BGET/BPUT
;; ------------------------------------------
IF PATCH_SD
.LAAD9 CMP #&09         ;; C=0 for read, C=1 for write
       PHP
       JSR MMC_BEGIN    ;; Initialize the card, if not already initialized
       PLP
       JSR MMC_SetupRW  ;; Setup SD card command block        
       JMP setRandomAddress ;; Set the sector addess from &C201,X .. &C203,X        
ELIF PATCH_IDE
.LAAD9 PHA
       JSR L8328        ;; Wait for ensuring to complete
       JSR WaitNotBusy
       LDA #1           ;; one sector
       STA &FC42
       CLC
       LDA ABSWS+&0201,X      ;; Set sector b0-b5
       AND #63
       ADC #1
       STA &FC43
       LDA ABSWS+&0202,X      ;; Set sector b8-b15
       STA &FC44
       LDA ABSWS+&0203,X      ;; Set sector b16-b21
       STA ABSWS+&0333
       JMP SetRandom
       EQUB &00         ;; Junk - so a binary compare will pass
       JMP L831E        ;; Junk - so a binary compare will pass
ELSE
.LAAD9 PHA
       JSR L8328        ;; Wait for ensuring to complete
       JSR L8080        ;; Set SCSI to command mode
       PLA
       JSR L831E        ;; Send command
       LDA ABSWS+&0203,X
       STA ABSWS+&0333
       JSR L831E        ;; Send sector address
       LDA ABSWS+&0202,X
       JSR L831E
       LDA ABSWS+&0201,X
       JSR L831E
       LDA #&01         ;; Send '1 sector'
       JSR L831E
       LDA #&00
       JMP L831E
ENDIF
;;
.LAB03 JSR LACE6        ;; Check checksum
.LAB06 JSR LABB4        ;; Check for data lost
       LDA ABSWS+&0204,X
       CMP #&C0
       BCC LAB88
       TXA
       LSR A
       LSR A
       ADC #>(ABSWS+&0900)
       STA &BD
       LDA #&00
       STA &BC
       LDA ABSWS+&0204,X
       AND #&BF
       STA ABSWS+&0204,X
       AND #&1E
       ROR A
       ORA #&30
       STA ABSWS+&02D4
       LDA ABSWS+&0201,X
       STA ABSWS+&02D0
       LDA ABSWS+&0202,X
       STA ABSWS+&02D1
       LDA ABSWS+&0203,X
       STA ABSWS+&02D2
       JSR LB56C        ;; ?
       JSR L8099        ;; Set default retries
       STX &C1
IF INCLUDE_FLOPPY
       LDA &CD          ;; Get hard drive presence
       AND #&20
       BEQ LAB50        ;; No hard drive, jump forward to do floppy
       LDA ABSWS+&0203,X ;; Get drive
       BPL LAB5E        ;; Hard drive, jump ahead
.LAB50 LDX &C1
       JSR LBA51
       BEQ LAB86
       DEC &CE
       BPL LAB50
       JMP L82BD        ;; Generate disk error
ENDIF
;;
;; BPUT to hard drive
;; --------------------
.LAB5E LDX &C1          ;; Get something
       LDA #&0A         ;; &0A - Write
       JSR LAAD9        ;; Send command block to SCSI/IDE/SD
       LDY #&00
       JSR L8332        ;; Wait for SCSI not busy
IF PATCH_IDE OR PATCH_SD
       BRA LAB76        ;; Always jump to write
.ResultCodes
       EQUB &12
       EQUB &06
       EQUB &2F
       EQUB &02
       EQUB &10
       EQUB &28
       EQUB &11
       EQUB &19
       EQUB &03
       EQUB >L82BD      ;; Junk - so a binary compare will pass
ELSE
       BPL LAB76        ;; Jump ahead with writing
       JSR L81AD        ;; Release Tube, get SCSI status
       DEC &CE          ;; Decrease retries
       BPL LAB5E        ;; Loop to try again
       JMP L82BD        ;; Generate a disk error
ENDIF
;;
;; Write a BPUT buffer to hard drive
;; ---------------------------------
IF PATCH_SD
.LAB76 LDA &B2
       PHA
       LDA &B3
       PHA
       LDA &BC
       STA &B2
       LDA &BD
       STA &B3
       JSR MMC_StartWrite
       JSR MMC_Write256
       JSR MMC_EndWrite
       PLA
       STA &B3
       PLA
       STA &B2
ELSE
.LAB76 LDA (&BC),Y      ;; Get byte from buffer
       STA &FC40        ;; Send to SCSI
       INY
       BNE LAB76        ;; Loop for 256 bytes
ENDIF
       LDA #&01
       TSB &CD
       DEY
IF PATCH_IDE OR PATCH_SD
       NOP              ;; Don't trample on IDE register
       NOP
       NOP
ELSE
       STY &FC43        ;; Set &FC43 to &FF
ENDIF
.LAB86 LDX &C1
.LAB88 RTS
;;
;; Service 5 - Interupt occured
;; ============================
IF PATCH_IDE OR PATCH_SD
.LAB89 RTS              ;; Remove IRQ routine
;;
.UpdateDrive
       LDA &85          ;; Merge with current drive
       ORA ABSWS+&0317
       STA &85
       STA ABSWS+&0333  ;; Store for any error
       LDA #&7F
       RTS
       EQUB &03         ;; Junk - so a binary compare will pass
                        ;; 13 spare bytes
                        ;; next=&ABB4
ELSE
.LAB89 LDA &CD          ;; Get flags
       AND #&21         ;; Check for hard drive+IRQ pending
       CMP #&21
       BNE LAB98        ;; No hard drive or IRQ pending
       JSR L806F        ;; Get SCSI status
       CMP #&F2
       BEQ LAB9B
ENDIF
.LAB98 LDA #&05         ;; Return from service call
       RTS
;;
.LAB9B PHY              ;; Send something to SCSI
       LDA #&00
       STA &FC43
       LDA #&01
       TRB &CD
       LDA &FC40
       JSR L8332
       ORA &FC40
       STA ABSWS+&0331
       JMP L9DB4        ;; Restore Y,X, claim call
;;
;;
;; Check for data loss
;; ===================
.LABB4 LDA ABSWS+&0331
       BEQ LABE6        ;; Jump forward to exit
       LDA #&00
       STA ABSWS+&0331        ;; Clear the flag
       LDX ABSWS+&02D4
       JSR L8374        ;; Generate 'Data lost' error
       EQUB &CA         ;; ERR=202
       EQUS "Data lost, channel"
       EQUB &00
;;
.LABD8 TXA
       STX ABSWS+&02A1
       LSR A
       LSR A
       ADC #&C9
       STA &BF
       LDA #&00
       STA &BE
.LABE6 RTS
;;
;;
.LABE7 LDX #&10
       STX ABSWS+&0295
       TAY
.LABED LDA ABSWS+&0204,X
       AND #&01
       BEQ LABF7
       STX ABSWS+&0295
.LABF7 LDA ABSWS+&0204,X
       BPL LAC71
       LDA ABSWS+&0201,X
       CMP ABSWS+&0296
       BNE LAC71
       LDA ABSWS+&0202,X
       CMP ABSWS+&0297
       BNE LAC71
       LDA ABSWS+&0203,X
       CMP ABSWS+&0298
       BNE LAC71
       JSR LABD8
.LAC17 TYA
       LSR A
       AND #&40
       ORA ABSWS+&0204,X
       ROR A
       AND #&E0
       ORA &CF
       PHP
       CLC
       ROL A
       STA ABSWS+&0204,X
       PLP
       BCC LAC4A
       LDY #&10
.LAC2E LDA ABSWS+&0204,Y
       BNE LAC3A
       LDA #&01
       STA ABSWS+&0204,Y
       BNE LAC6E
.LAC3A DEY
       DEY
       DEY
       DEY
       BPL LAC2E
       JSR LAD04
       ROR ABSWS+&0204,X
       SEC
       ROL ABSWS+&0204,X
.LAC4A INX
       INX
       INX
       INX
       CPX #&11
       BCC LAC54
       LDX #&00
.LAC54 LDA ABSWS+&0204,X
       LSR A
       BEQ LAC6E
       BCC LAC6E
       CLC
       ROL A
       STA ABSWS+&0204,X
       JSR LAD04
       JSR LAD04
       ROR ABSWS+&0204,X
       SEC
       ROL ABSWS+&0204,X
.LAC6E JMP LAB03
;;
.LAC71 DEX
       DEX
       DEX
       DEX
       BMI LAC7A
       JMP LABED
;;
.LAC7A LDX ABSWS+&0295
       LDA ABSWS+&0296
       STA ABSWS+&0201,X
       STA ABSWS+&02D0
       LDA ABSWS+&0297
       STA ABSWS+&0202,X
       STA ABSWS+&02D1
       LDA ABSWS+&0298
       STA ABSWS+&0203,X
       STA ABSWS+&02D2
       JSR LABD8
       LDA ABSWS+&0298
       JSR LB56C
       STY &B1
       STX &B0
       JSR L8099
.LACA8 LDX &B0
IF INCLUDE_FLOPPY
       LDA &CD
       AND #&20
       BEQ LACB5
ENDIF
       LDA ABSWS+&0203,X
       BPL LACC1
IF INCLUDE_FLOPPY
.LACB5 JSR LBA54
       BEQ LACDA
ENDIF
.LACBA DEC &CE          ;; Decrement retries
       BPL LACA8        ;; Loop to rey again
       JMP L82BD        ;; Generate a disk error
;;
;; BGET from hard drive
;; --------------------
.LACC1 LDA #&08         ;; &08 - READ
       JSR LAAD9        ;; Send command block to SCSI
       JSR L8332        ;; Wait for SCSI not busy
IF PATCH_IDE OR PATCH_SD
       NOP
       NOP
ELSE
       BMI LACD5        ;; If SCSI writing, finish
ENDIF
       LDY #&00
IF PATCH_SD     
.LACCD LDA &B2
       PHA
       LDA &B3
       PHA
       LDA &BE
       STA &B2
       LDA &BF
       STA &B3
       JSR MMC_StartRead
       JSR MMC_Read256
       JSR MMC_16Clocks	;; ignore CRC
       PLA
       STA &B3
       PLA
       STA &B2
       ;; TODO Add error handling
ELSE        
.LACCD LDA &FC40        ;; Get byte from SCSI
       STA (&BE),Y      ;; Store to buffer
       INY
       BNE LACCD        ;; Loop for 256 bytes
ENDIF
.LACD5 JSR L81AD        ;; Release and get result
       BNE LACBA        ;; Retry with error
.LACDA LDX &B0          ;; Restore X & Y
       LDY &B1
       LDA #&81
       STA ABSWS+&0204,X
       JMP LAC17
;;
.LACE6 LDX #&10
.LACE8 LDA ABSWS+&0204,X
       AND #&01
       BNE LAD24
       DEX
       DEX
       DEX
       DEX
       BPL LACE8
       JMP LA76E
;;
.LACF8 JSR L836B
       EQUB &DE         ;; ERR=222
       EQUS "Channel"
       EQUB &00
;;
.LAD04 DEX
       DEX
       DEX
       DEX
       BPL LAD0C
       LDX #&10
.LAD0C RTS
;;
;; Check channel and get channel flags
;; -----------------------------------
.LAD0D STY &C2          ;; Save channel
       STY ABSWS+&02D5
       CPY #&3A         ;; Check channel is in range
       BCS LACF8        ;; Too high - error
       TYA
       SEC
       SBC #&30
       BCC LACF8        ;; Too low - error
       STA &CF          ;; Store channel offset
       TAX
       LDA ABSWS+&03AC,X      ;; Get channel flags
       BEQ LACF8        ;; Channel not open - error
.LAD24 RTS
;;
;; &C3AC,X channel flags
;; &C334,X
;; &C33E,X
;; &C348,X
;; &C352,X
;; &C35C,X
;; &C366,X
;; &C370,X
;; &C37A,X
;;
;; Compare something
;; -----------------
.LAD25 LDX &CF          ;; Get channel offset
       LDA ABSWS+&0334,X
       CMP ABSWS+&035C,X      ;; Compare something
       BNE LAD48        ;; Different, so end with NE+CC/CS
       LDA ABSWS+&033E,X
       CMP ABSWS+&0366,X      ;; Compare something
       BNE LAD48        ;; Different, so end with NE+CC/CS
       LDA ABSWS+&0348,X
       CMP ABSWS+&0370,X      ;; Compare something
       BNE LAD48        ;; Different, so end with NE+CC/CS
       LDA ABSWS+&0352,X
       CMP ABSWS+&037A,X      ;; Compare something
       BNE LAD48        ;; Different, so end with NE+CC/CS
       CLC              ;; All same, set EQ+CC
.LAD48 RTS
;;
;; FSC 1 - Read EOF
;; ================
.LAD49 LDY &B4
       JSR LAD0D
       ROR A
       BCS LAD5A
       JSR LA77F
       JSR LB1E9
       JSR LAD25
.LAD5A LDX #&00
       BCS LAD5F
       DEX
.LAD5F LDY &B5
       RTS
;;
.LAD62 LDA ABSWS+&03AC,X
       AND #&C8
       STA ABSWS+&03AC,X
       JSR L836B        ;; Generate an error
       EQUB &DF         ;; ERR=150
       EQUS "EOF"
       EQUB &00
;;
;; OSBGET
;; ======
.LAD72 STX &C3          ;; Save X
       JSR LAD0D        ;; Check channel and get flags
       ROR A
       BCS LAD9C
       AND #&04         ;; Gone past EOF?
       BNE LAD62        ;; Generate EOF error
       JSR LAD25        ;; Compare something
       BCS LAD9C        ;; CS+NE, ok to read byte
       BNE LAD62        ;; Not same, so generate 'EOF' error
       JSR LA77F        ;; Check various checksums
       LDX &CF          ;; Get offset to channel
       LDA ABSWS+&03AC,X      ;; Get channel flag
       AND #&C0
       ORA #&08         ;; Set EOF flag
       STA ABSWS+&03AC,X
       LDY &C2          ;; Restore Y
       LDX &C3          ;; Restore X
       SEC              ;; Flag EOF
       LDA #&FE         ;; EOF value
       RTS              ;; Return
;;
;; Read byte from channel
;; ----------------------
.LAD9C LDX &CF          ;; Get channel offset
       CLC
       LDA ABSWS+&03CA,X
       ADC ABSWS+&0370,X
       STA ABSWS+&0296
       LDA ABSWS+&03C0,X
       ADC ABSWS+&0366,X
       STA ABSWS+&0297
       LDA ABSWS+&03B6,X
       ADC ABSWS+&035C,X
       STA ABSWS+&0298        ;; &C296/7/8=&C3CA/B/C,X+&C370/1/2,X
       LDA #&40
       JSR LABE7        ;; Manipulate various things
       LDX &CF
       LDY ABSWS+&037A,X
       LDA #&00
       STA ABSWS+&02CF
       JSR LB180
       LDA (&BE),Y      ;; Get byte from buffer
       LDY &C2          ;; Restore Y
       LDX &C3          ;; Restore X
       CLC              ;; Clear EOF flag
       RTS              ;; Return
;;
.LADD4 LDY #&02
.LADD6 LDA ABSWS+&0314,Y
       STA ABSWS+&0230,Y
       DEY
       BPL LADD6
       LDA ABSWS+&0317
       STA ABSWS+&0233
       LDX &CF
       LDA ABSWS+&03B6,X
       AND #&E0
       STA ABSWS+&022F
       LDA ABSWS+&03E8,X
       STA ABSWS+&022C
       LDA ABSWS+&03DE,X
       STA ABSWS+&022D
       LDA ABSWS+&03D4,X
       STA ABSWS+&022E
       JSR L89D8
       LDY #&02
.LAE06 LDA ABSWS+&0230,Y
       STA ABSWS+&022C,Y
       DEY
       BPL LAE06
       LDA ABSWS+&0233
       STA ABSWS+&022F
       JSR LB4DF
       LDX &CF
       LDA ABSWS+&03CA,X
       STA ABSWS+&0234
       LDA ABSWS+&03C0,X
       STA ABSWS+&0235
       LDA ABSWS+&03B6,X
       AND #&1F
       STA ABSWS+&0236
       LDA #<(ABSWS+&0405)
       STA &B8
       LDA #>(ABSWS+&0405)
       STA &B9
       LDX &CF
.LAE38 LDY #&00
       LDA (&B8),Y
       BNE LAE44
       STA ABSWS+&03AC,X
       JMP LA76E
;;
.LAE44 LDY #&19
       LDA (&B8),Y
       CMP ABSWS+&03F2,X
       BNE LAE5B
       DEY
.LAE4E LDA (&B8),Y
       CMP ABSWS+&021E,Y
       BNE LAE5B
       DEY
       CPY #&16
       BCS LAE4E
       RTS
;;
.LAE5B LDA &B8
       CLC
       ADC #&1A
       STA &B8
       BCC LAE38
       INC &B9
       BCS LAE38
.LAE68 LDA #&00
       STA ABSWS+&02B5
.LAE6D LDA ABSWS+&022F
       STA ABSWS+&02BF
       LDX #&02
.LAE75 LDA ABSWS+&022C,X
       STA ABSWS+&02BC,X
       DEX
       BPL LAE75
       LDA #&FF
       STA ABSWS+&022E
       STA ABSWS+&022F
       LDX &CF
       LDA ABSWS+&0384,X
       CMP ABSWS+&029D
       BNE LAEA6
       LDA ABSWS+&038E,X
       CMP ABSWS+&029C
       BNE LAEA6
       LDA ABSWS+&0398,X
       CMP ABSWS+&029B
       BNE LAEA6
       LDA ABSWS+&03A2,X
       CMP ABSWS+&029A
.LAEA6 BCC LAED0
       LDA ABSWS+&0334,X
       CMP ABSWS+&029D
       BNE LAECB
       LDA ABSWS+&033E,X
       CMP ABSWS+&029C
       BNE LAECB
       LDA ABSWS+&0348,X
       CMP ABSWS+&029B
       BNE LAECB
       LDA ABSWS+&0352,X
       CMP ABSWS+&029A
       BNE LAECB
.LAEC8 JMP LB0DA
;;
.LAECB BCS LAEC8
       JMP LAFE4
;;
.LAED0 JSR LADD4
       LDA ABSWS+&03A2,X
       CMP #&01
       LDA ABSWS+&0398,X
       ADC #&00
       STA ABSWS+&0237
       LDA ABSWS+&038E,X
       ADC #&00
       STA ABSWS+&0238
       LDA ABSWS+&0384,X
       ADC #&00
       STA ABSWS+&0239
       JSR L84E1
       STZ ABSWS+&023D
       STZ ABSWS+&023E
       STZ ABSWS+&023F
       LDX ABSWS+&01FE
.LAEFF LDA ABSWS+&023F
       CMP ABSWS+&00FF,X
       BCC LAF1B
       BNE LAF2A
       LDA ABSWS+&023E
       CMP ABSWS+&00FE,X
       BCC LAF1B
       BNE LAF2A
       LDA ABSWS+&023D
       CMP ABSWS+&00FD,X
       BCS LAF2A
.LAF1B LDY #&02
.LAF1D LDA ABSWS+&00FF,X
       STA ABSWS+&023D,Y
       DEX
       DEY
       BPL LAF1D
       TXA
       BRA LAF2D
;;
.LAF2A DEX
       DEX
       DEX
.LAF2D BNE LAEFF
       LDX #&03
.LAF31 LDA ABSWS+&023C,X
       CMP ABSWS+&029A,X
       BNE LAF3F
       DEX
       BNE LAF31
       CPX ABSWS+&029A
.LAF3F LDA ABSWS+&029C
       LDY ABSWS+&029D
       INC A
       BNE LAF4E
       INY
       BNE LAF4E
       JMP L867F
;;
.LAF4E BCC LAF5E
       CPY ABSWS+&023F
       BCC LAF5E
       BNE LAF67
       CMP ABSWS+&023E
       BCC LAF5E
       BNE LAF67
.LAF5E STY ABSWS+&023F
       STA ABSWS+&023E
       STZ ABSWS+&023D
.LAF67 JSR L865B
       LDY #&12
       LDA #&00
       LDX &CF
       STA (&B8),Y
       STA ABSWS+&03A2,X
       INY
       LDA ABSWS+&023D
       STA (&B8),Y
       STA ABSWS+&0398,X
       LDA ABSWS+&023E
       INY
       STA (&B8),Y
       STA ABSWS+&038E,X
       LDA ABSWS+&023F
       INY
       STA (&B8),Y
       STA ABSWS+&0384,X
       LDA ABSWS+&023A
       INY
       STA (&B8),Y
       STA ABSWS+&03CA,X
       LDA ABSWS+&023B
       INY
       STA (&B8),Y
       STA ABSWS+&03C0,X
       LDA ABSWS+&023C
       INY
       STA (&B8),Y
       ORA ABSWS+&0317
       STA ABSWS+&03B6,X
       JSR L8F91
       LDA #&08
       TRB &CD
       LDA #&C4
       STA ABSWS+&0260
       LDA #&09
       STA ABSWS+&0261
       LDX #&00
       LDY #&02
.LAFC3 LDA ABSWS+&0234,Y
       STA ABSWS+&02A2,Y
       CMP ABSWS+&023A,Y
       BEQ LAFD2
       INX
       LDA ABSWS+&023A,Y
.LAFD2 STA ABSWS+&02A8,Y
       LDA ABSWS+&0237,Y
       STA ABSWS+&02A5,Y
       DEY
       BPL LAFC3
       TXA
       BEQ LAFE4
       JSR L96AC
.LAFE4 LDA ABSWS+&02B5
       BEQ LAFEC
       JMP LB0BD
;;
.LAFEC LDX &CF
       CLC
       LDA ABSWS+&0348,X
       ADC ABSWS+&03CA,X
       STA ABSWS+&0296
       LDA ABSWS+&033E,X
       ADC ABSWS+&03C0,X
       STA ABSWS+&0297
       LDA ABSWS+&0334,X
       ADC ABSWS+&03B6,X
       STA ABSWS+&0298
       LDA #&C0
       JSR LABE7
       LDX &CF
       LDY ABSWS+&0352,X
       LDA #&00
.LB016 STA (&BE),Y
       INY
       BNE LB016
       LDA ABSWS+&029B
       CLC
       ADC ABSWS+&03CA,X
       STA ABSWS+&0234
       LDA ABSWS+&029C
       ADC ABSWS+&03C0,X
       STA ABSWS+&0235
       LDA ABSWS+&029D
       ADC ABSWS+&03B6,X
       STA ABSWS+&0236
       LDA ABSWS+&029A
       BNE LB04F
       LDA ABSWS+&0234
       BNE LB04C
       LDA ABSWS+&0235
       BNE LB049
       DEC ABSWS+&0236
.LB049 DEC ABSWS+&0235
.LB04C DEC ABSWS+&0234
.LB04F LDA ABSWS+&0234
       CMP ABSWS+&0296
       BNE LB06A
       LDA ABSWS+&0235
       CMP ABSWS+&0297
       BNE LB06A
       LDA ABSWS+&0236
       CMP ABSWS+&0298
       BNE LB06A
       JMP LB0BD
;;
.LB06A JSR L8328
       INC ABSWS+&0296
       BNE LB07A
       INC ABSWS+&0297
       BNE LB07A
       INC ABSWS+&0298
.LB07A LDA #&40
       JSR LABE7
       LDY #&00
       TYA
.LB082 STA (&BE),Y
       INY
       BNE LB082
.LB087 LDX ABSWS+&02A1
       LDA #&C0
       ORA ABSWS+&0204,X
       STA ABSWS+&0204,X
       JSR LAB06
       LDA ABSWS+&0234
       CMP ABSWS+&0201,X
       BNE LB0AD
       LDA ABSWS+&0235
       CMP ABSWS+&0202,X
       BNE LB0AD
       LDA ABSWS+&0236
       CMP ABSWS+&0203,X
       BEQ LB0BD
.LB0AD INC ABSWS+&0201,X
       BNE LB087
       INC ABSWS+&0202,X
       BNE LB087
       INC ABSWS+&0203,X
       JMP LB087
;;
.LB0BD LDX &CF
       LDA ABSWS+&029A
       STA ABSWS+&0352,X
       LDA ABSWS+&029B
       STA ABSWS+&0348,X
       LDA ABSWS+&029C
       STA ABSWS+&033E,X
       LDA ABSWS+&029D
       STA ABSWS+&0334,X
       JSR L89D8
.LB0DA LDA ABSWS+&02BF
       STA ABSWS+&022F
       LDX #&02
.LB0E2 LDA ABSWS+&02BC,X
       STA ABSWS+&022C,X
       DEX
       BPL LB0E2
       RTS
;;
;; OSBPUT
;; ======
.LB0EC STX &C3          ;; Save X
       PHA              ;; Save output byte
       JSR LAD0D        ;; Check channel and get flags
       LDY #&00
       STY ABSWS+&02CF
       TAY
       BMI LB112
.LB0FA JSR L836B
       EQUB &C1         ;; ERR=193
       EQUS "Not open for update"
       EQUB &00
;;
.LB112 LDA ABSWS+&03AC,X
       AND #&07
       CMP #&06
       BCS LB14D
       CMP #&03
       BEQ LB14D
       LDA ABSWS+&037A,X
       SEC
       ADC #&00
       STA ABSWS+&029A
       LDA ABSWS+&0370,X
       ADC #&00
       STA ABSWS+&029B
       LDA ABSWS+&0366,X
       ADC #&00
       STA ABSWS+&029C
       LDA ABSWS+&035C,X
       ADC #&00
       STA ABSWS+&029D
       PLA
       JSR LA77F
       PHA
       DEC ABSWS+&02CF
       JSR LAE68
       LDX &CF
.LB14D CLC
       LDA ABSWS+&03CA,X
       ADC ABSWS+&0370,X
       STA ABSWS+&0296
       LDA ABSWS+&03C0,X
       ADC ABSWS+&0366,X
       STA ABSWS+&0297
       LDA ABSWS+&03B6,X
       ADC ABSWS+&035C,X
       STA ABSWS+&0298
       LDA #&C0
       JSR LABE7
       LDX &CF
       LDY &C37A,X
       PLA
       STA (&BE),Y
       PHA
       JSR LB180
       PLA
       LDY &C2
       LDX &C3
.LB17F RTS
;;
.LB180 LDX &CF
       INC ABSWS+&037A,X
       BNE LB17F
       BIT ABSWS+&02CF
       BMI LB18F
       JSR LA77F
.LB18F INC ABSWS+&0370,X
       BNE LB19C
       INC ABSWS+&0366,X
       BNE LB19C
       INC ABSWS+&035C,X
.LB19C JSR LB1E9
       PHA
       SEC
       LDA ABSWS+&0370,X
       SBC ABSWS+&0348,X
       LDA ABSWS+&0366,X
       SBC ABSWS+&033E,X
       LDA ABSWS+&035C,X
       SBC ABSWS+&0334,X
       BCC LB1DE
       LDA ABSWS+&037A,X
       CMP ABSWS+&0352,X
       BNE LB1C1
       PLA
       ORA #&04
       PHA
.LB1C1 SEC
       LDA ABSWS+&0348,X
       SBC ABSWS+&0398,X
       LDA ABSWS+&033E,X
       SBC ABSWS+&038E,X
       LDA ABSWS+&0334,X
       SBC ABSWS+&0384,X
       BCC LB1D9
       PLA
       BNE LB1E1
.LB1D9 PLA
       ORA #&02
       BNE LB1E1
.LB1DE PLA
       ORA #&03
.LB1E1 BMI LB1E5
       AND #&F9
.LB1E5 STA ABSWS+&03AC,X
       RTS
;;
.LB1E9 LDX &CF          ;; Get channel offset
       LDA ABSWS+&03AC,X
       PHA
       AND #&04
       BEQ LB20B
       LDA ABSWS+&037A,X
       STA ABSWS+&0352,X
       LDA ABSWS+&0370,X
       STA ABSWS+&0348,X
       LDA ABSWS+&0366,X
       STA ABSWS+&033E,X
       LDA ABSWS+&035C,X
       STA ABSWS+&0334,X
.LB20B PLA
       AND #&C0
       BNE LB1E5
.LB210 LDA #&00         ;; A=0 for CLOSE
       TAY              ;; CLOSE#0 - close all open channels
;;
;;
;; OSFIND - Open a file or close a channel
;; =======================================
.LB213 JSR LA77F        ;; Check checksums
       STX ABSWS+&0240
       STX &B4
       STX &C5          ;; Store X -> filename
       STY &C4
       STY ABSWS+&0241
       STY &B5          ;; Store Y -> filename
       AND #&C0         ;; Open or close?
       LDY #&00
       STY ABSWS+&02D5
       TAY              ;; Zero A and Y
       BNE LB231        ;; Jump ahead for open
       JMP LB3E0        ;; Jump to close
;;
;; OPEN
;; ----
.LB231 LDA ABSWS+&0332  ;; Handle stored from *RUN?
       BEQ LB23E        ;; No, do a real OPEN
       LDY #&00
       STY ABSWS+&0332  ;; Clear stored handle
       LDY &B5          ;; Restore Y
       RTS              ;; Return handle from *RUN
;;
;; Open a file
;; -----------
.LB23E LDX #&09         ;; Look for a spare channel
.LB240 LDA ABSWS+&03AC,X      ;; Check channel flags
       BEQ LB260        ;; Found a spare channel
       DEX              ;; Loop to next channel
       BPL LB240        ;; Keep going until run out of channels
       JSR L836B        ;; Generate an error
       EQUB &C0         ;; ERR=192
       EQUS "Too many open files"
       EQUB &00
;;
;; Found a spare channel
;; ---------------------
.LB260 STX &CF          ;; Store channel offset
       STY ABSWS+&02A0
       TYA
       BPL LB26B
       JMP LB33E
;;
.LB26B JSR L8FE8
       BEQ LB275
       LDA #&00
       JMP LB336
;;
.LB275 LDX #&09
.LB277 LDA ABSWS+&03AC,X
       BPL LB2AA
       LDA ABSWS+&03B6,X
       AND #&E0
       CMP ABSWS+&0317
       BNE LB2AA
       LDA ABSWS+&03E8,X
       CMP ABSWS+&0314
       BNE LB2AA
       LDA ABSWS+&03DE,X
       CMP ABSWS+&0315
       BNE LB2AA
       LDA ABSWS+&03D4,X
       CMP ABSWS+&0316
       BNE LB2AA
       LDY #&19
       LDA (&B6),Y
       CMP ABSWS+&03F2,X
       BNE LB2AA
       JMP L8D5E
;;
.LB2AA DEX
       BPL LB277
       LDY #&00
       LDA (&B6),Y
       BMI LB2B6
       JMP L8BFB
;;
.LB2B6 LDY #&12
       LDX &CF
       LDA (&B6),Y
       STA ABSWS+&0352,X
       INY
       LDA (&B6),Y
       STA ABSWS+&0348,X
       INY
       LDA (&B6),Y
       STA ABSWS+&033E,X
       INY
       LDA (&B6),Y
       STA ABSWS+&0334,X
.LB2D1 LDY #&12
       LDX &CF
       LDA (&B6),Y
       STA ABSWS+&03A2,X
       INY
       LDA (&B6),Y
       STA ABSWS+&0398,X
       INY
       LDA (&B6),Y
       STA ABSWS+&038E,X
       INY
       LDA (&B6),Y
       STA ABSWS+&0384,X
       INY
       LDA (&B6),Y
       STA ABSWS+&03CA,X
       INY
       LDA (&B6),Y
       STA ABSWS+&03C0,X
       INY
       LDA (&B6),Y
       ORA ABSWS+&0317
       STA ABSWS+&03B6,X
       INY
       LDA (&B6),Y
       STA ABSWS+&03F2,X
       LDA ABSWS+&0314
       STA ABSWS+&03E8,X
       LDA ABSWS+&0315
       STA ABSWS+&03DE,X
       LDA ABSWS+&0316
       STA ABSWS+&03D4,X
       LDA #&00
       STA ABSWS+&037A,X
       STA ABSWS+&0370,X
       STA ABSWS+&0366,X
       STA ABSWS+&035C,X
       LDA ABSWS+&02A0
       STA ABSWS+&03AC,X
       TXA
       CLC
       ADC #&30
       PHA
       JSR LB19C
       PLA
.LB336 JSR L89D8
       LDX &C5
       LDY &C4
       RTS
;;
.LB33E BIT ABSWS+&02A0
       BVC LB35B
       JSR L8FE8
       PHP
       LDA #&00
       PLP
       BNE LB336
       JSR L8D2C
       LDY #&01
       LDA (&B6),Y
       BMI LB358
.LB355 JMP L8BFB
;;
.LB358 JMP LB275
;;
.LB35B JSR L8DC8
       JSR L8FE8
       BNE LB36F
       JSR L8D1B
       LDY #&01
       LDA (&B6),Y
       BPL LB355
       JMP LB3CD
;;
.LB36F LDA #&00
       LDX #&0F
.LB373 STA ABSWS+&0242,X
       DEX
       BPL LB373
       LDX ABSWS+&01FE
       LDA #&00
.LB37E ORA ABSWS+&00FE,X
       ORA ABSWS+&00FF,X
       LDY ABSWS+&00FD,X
       CPY ABSWS+&024F
       BCC LB38F
       STY ABSWS+&024F
.LB38F DEX
       DEX
       DEX
       BNE LB37E
       TAY
       BEQ LB39E
       STX ABSWS+&024F
       INX
       STX ABSWS+&0250
.LB39E LDA #&FF
       STA ABSWS+&0246
       STA ABSWS+&0247
       STA ABSWS+&0248
       STA ABSWS+&0249
       LDX #<(ABSWS+&0240)
       STX &B8
       LDY #>(ABSWS+&0240)
       STY &B9
       JSR L89D8
       JSR L8F57
       JSR L8F91
       JSR L89D5
       LDA ABSWS+&0240
       STA &B4
       LDA ABSWS+&0241
       STA &B5
       JSR L8FE8
.LB3CD LDA #&00
       LDX &CF
       STA ABSWS+&0352,X
       STA ABSWS+&0348,X
       STA ABSWS+&033E,X
       STA ABSWS+&0334,X
       JMP LB2D1
;;
;; CLOSE a channel
;; ===============
.LB3E0 LDY &C4          ;; Get handle
       BNE LB406        ;; Nonzero, close just this channel
       LDX #&09         ;; Loop for all channels
.LB3E6 LDA ABSWS+&03AC,X      ;; Get channel flag
       BNE LB3F7        ;; Jump to close this channel
.LB3EB DEX              ;; Loop for all channels
       BPL LB3E6
       JSR L8328        ;; Wait until ensuring complete
       LDA #&00         ;; Clear A
       LDX &C5          ;; Restore X
       TAY              ;; Clear Y
       RTS              ;; Returns with A and Y preserved
;;
;; Close a channel with X=offset
;; -----------------------------
.LB3F7 TXA
       CLC
       ADC #&30         ;; A=channel number for this offset
       STA &B5
       STX &CF          ;; Save X
       JSR LB409        ;; Close this channel
       LDX &CF          ;; Restore X
       BPL LB3EB        ;; Jump back into close-all loop
;;
;; Close a channel with Y=handle
;; -----------------------------
.LB406 JSR LAD0D        ;; Check channel and get flags
.LB409 JSR LB1E9        ;; Check something and set flags
       LDY ABSWS+&03AC,X      ;; Get flags
       STZ ABSWS+&03AC,X      ;; Clear flags
       TYA              ;; Pass flags to A
       BPL LB435        ;; Jump ahead if b7=0
       LDA ABSWS+&0352,X
       CMP ABSWS+&03A2,X
       BNE LB442
       LDA ABSWS+&0348,X
       CMP ABSWS+&0398,X
       BNE LB442
       LDA ABSWS+&033E,X
       CMP ABSWS+&038E,X
       BNE LB442
       LDA ABSWS+&0334,X
       CMP ABSWS+&0384,X
       BNE LB442        ;; Jump ahead with difference
.LB435 JSR LAAB9        ;; Write buffer?
       JSR L89D8        ;; Do something with FSM
       LDA #&00
       LDY &C4
       LDX &C5
       RTS
;;
;; Update directory entry?
;; -----------------------
.LB442 JSR LADD4
       LDA ABSWS+&0352,X
       CMP #&01
       LDA ABSWS+&0234
       ADC ABSWS+&0348,X
       STA ABSWS+&0234
       LDA ABSWS+&0235
       ADC ABSWS+&033E,X
       STA ABSWS+&0235
       LDA ABSWS+&0236
       ADC ABSWS+&0334,X
       STA ABSWS+&0236
       LDA ABSWS+&03A2,X
       CMP #&01
       LDA ABSWS+&0398,X
       SBC ABSWS+&0348,X
       STA ABSWS+&0237
       LDA ABSWS+&038E,X
       SBC ABSWS+&033E,X
       STA ABSWS+&0238
       LDA ABSWS+&0384,X
       SBC ABSWS+&0334,X
       STA ABSWS+&0239
       LDA ABSWS+&0352,X
       BNE LB497
       INC ABSWS+&0237
       BNE LB497
       INC ABSWS+&0238
       BNE LB497
       INC ABSWS+&0239
.LB497 LDA ABSWS+&0352,X
       LDY #&12
       STA (&B8),Y
       LDA ABSWS+&0348,X
       INY
       STA (&B8),Y
       LDA ABSWS+&033E,X
       INY
       STA (&B8),Y
       LDA ABSWS+&0334,X
       INY
       STA (&B8),Y
       JSR L84E1        ;; Calculate something in FSM
       JSR L8F91
       JMP LB435        ;; Jump back to write buffer?
;;
.LB4B9 LDX #&09
.LB4BB LDA ABSWS+&03AC,X
       BEQ LB4CA
       LDA ABSWS+&03B6,X
       AND #&E0
       CMP ABSWS+&0317
       BEQ LB4DF
.LB4CA DEX
       BPL LB4BB
;;
.LB4CD LDA ABSWS+&0317
       JSR LB5C5
       LDA ABSWS+&01FB
       STA ABSWS+&0321,X
       LDA ABSWS+&01FC
       STA ABSWS+&0322,X
.LB4DF JSR LB510
.LB4E2 LDA ABSWS+&0317
       JSR LB5C5
       LDA ABSWS+&01FB
       CMP ABSWS+&0321,X
       BNE LB4FF
       LDA ABSWS+&01FC
       CMP ABSWS+&0322,X
       BNE LB4FF
       JSR LB560
       STA ABSWS+&02C2
       RTS
;;
.LB4FF JSR L836B
       EQUB &C8         ;; ERR=200
       EQUS "Disc changed"
       EQUB &00
;;
.LB510 LDA #&01
       LDX #<(ABSWS+&02C8)
       LDY #>(ABSWS+&02C8)
       JSR &FFF1
       LDX #&00
       LDY #&04
       SEC
.LB51E LDA ABSWS+&02C8,X
       PHA
       SBC ABSWS+&02C3,X
       STA ABSWS+&02C8,X
       PLA
       STA ABSWS+&02C3,X
       INX
       DEY
       BPL LB51E
       LDA ABSWS+&02CC
       ORA ABSWS+&02CB
       ORA ABSWS+&02CA
       BNE LB542
       LDA ABSWS+&02C9
       CMP #&02
       BCC LB545
.LB542 STY ABSWS+&02C2
.LB545 RTS
;;
.LB546 JSR LB510
       LDA ABSWS+&0317
       JSR LB5C5
       JSR LB560
       EOR ABSWS+&02C2
       BEQ LB545
       LDX #<L8831
       LDY #>L8831
       JSR L82AE
       BRA LB4E2
;;
.LB560 LDA #&FF
       CLC
.LB563 ROL A
       DEX
       DEX
       BPL LB563
       AND ABSWS+&02C2
       RTS
;;
.LB56C AND #&E0
       STA ABSWS+&02CD
       PHX
       PHY
       JSR LB510
       LDA ABSWS+&02CD
       JSR LB5C5
       JSR LB560
       EOR ABSWS+&02C2
       BEQ LB5C2
       LDA ABSWS+&02CD
       TAX
       PHA
       LDA ABSWS+&0317
       STA ABSWS+&02CD
       LDY ABSWS+&022F
       CPY #&FF
       BNE LB59C
       STA ABSWS+&022F
       STY ABSWS+&02CD
.LB59C STX ABSWS+&0317
       JSR LB546
       LDY ABSWS+&02CD
       STY ABSWS+&0317
       CPY #&FF
       BNE LB5B5
       LDA ABSWS+&022F
       STA ABSWS+&0317
       STY ABSWS+&022F
.LB5B5 PLA
       CMP ABSWS+&0317
       BEQ LB5C2
       LDX #<L8831
       LDY #>L8831
       JSR L82AE
.LB5C2 PLY
       PLX
       RTS
;;
.LB5C5 LSR A
       LSR A
       LSR A
       LSR A
       TAX
       RTS
;;
.LB5CB JSR LA77F
       STA ABSWS+&02B4
       STA ABSWS+&02B5
       STY &C7
       STX &C6
       LDY #&01
       LDX #&03
.LB5DC LDA (&C6),Y
       STA ABSWS+&02B7,Y
       INY
       DEX
       BPL LB5DC
       LDA ABSWS+&02B4
       CMP #&05
       BCC LB5F0
       JMP LB8DA
;;
.LB5EF RTS
;;
.LB5F0 TAY
       BEQ LB5EF
       LDY #&00
       LDA (&C6),Y
       TAY
       JSR LAD0D
       PHP
       JSR LB1E9
       LDX &CF
       LDA ABSWS+&03B6,X
       JSR LB56C
       PLP
       BMI LB614
       LDA ABSWS+&02B4
       CMP #&03
       BCS LB614
       JMP LB0FA
;;
.LB614 LDA ABSWS+&02B4
       AND #&01
       BEQ LB629
       LDY #&0C
       LDX #&03
.LB61F LDA (&C6),Y
       STA &C8,X
       DEY
       DEX
       BPL LB61F
       LDA #&01
.LB629 LDY &C2
       LDX #&C8
       JSR LA9AB
       CLC
       LDX #&03
       LDY #&05
.LB635 LDA (&C6),Y
       ADC &00C3,Y
       STA ABSWS+&0295,Y
       INY
       DEX
       BPL LB635
       LDA ABSWS+&02B4
       STA ABSWS+&02B5
       CMP #&03
       BCS LB64E
       JSR LAE6D
.LB64E LDY #&09
       LDX &CF
       LDA ABSWS+&029A
       STA ABSWS+&037A,X
       STA (&C6),Y
       INY
       LDA ABSWS+&029B
       STA ABSWS+&0370,X
       STA (&C6),Y
       INY
       LDA ABSWS+&029C
       STA ABSWS+&0366,X
       STA (&C6),Y
       INY
       LDA ABSWS+&029D
       STA ABSWS+&035C,X
       STA (&C6),Y
       LDA ABSWS+&02B4
       CMP #&03
       BCS LB690
.LB67C LDX #&03
       LDY #&05
.LB680 LDA (&C6),Y
       STA ABSWS+&023B,Y
       LDA #&00
       STA (&C6),Y
       INY
       DEX
       BPL LB680
       JMP LB6FE
;;
.LB690 JSR LAD25
       BCS LB67C
       BEQ LB67C
       STZ ABSWS+&02B5
       LDX &CF
       SEC
       LDA ABSWS+&0352,X
       SBC &C8
       STA ABSWS+&0240
       LDA ABSWS+&0348,X
       SBC &C9
       STA ABSWS+&0241
       LDA ABSWS+&033E,X
       SBC &CA
       STA ABSWS+&0242
       LDA ABSWS+&0334,X
       SBC &CB
       STA ABSWS+&0243
       LDX #&03
       LDY #&05
       SEC
.LB6C2 LDA (&C6),Y
       SBC ABSWS+&023B,Y
       STA (&C6),Y
       INY
       DEX
       BPL LB6C2
       LDX &CF
       LDA ABSWS+&0352,X
       STA ABSWS+&029A
       STA ABSWS+&037A,X
       STA (&C6),Y
       INY
       LDA ABSWS+&0348,X
       STA ABSWS+&029B
       STA ABSWS+&0370,X
       STA (&C6),Y
       INY
       LDA ABSWS+&033E,X
       STA ABSWS+&029C
       STA ABSWS+&0366,X
       STA (&C6),Y
       INY
       LDA ABSWS+&0334,X
       STA ABSWS+&029D
       STA ABSWS+&035C,X
       STA (&C6),Y
.LB6FE LDY #&01
       LDX #&03
       CLC
.LB703 LDA ABSWS+&023F,Y
       ADC (&C6),Y
       STA (&C6),Y
       INY
       DEX
       BPL LB703
       LDA &C8
       BNE LB715
       JMP LB7A5
;;
.LB715 LDX &CF
       CLC
       LDA ABSWS+&03CA,X
       ADC &C9
       STA ABSWS+&0296
       LDA ABSWS+&03C0,X
       ADC &CA
       STA ABSWS+&0297
       LDA ABSWS+&03B6,X
       ADC &CB
       STA ABSWS+&0298
       LDA #&02
       CMP ABSWS+&02B4
       LDA #&80
       ROR A
       JSR LABE7
       LDA &C8
       STA ABSWS+&02B6
       STZ ABSWS+&02B7
       LDX #&02
.LB745 LDA ABSWS+&029B,X
       CMP &C9,X
       BNE LB768
       DEX
       BPL LB745
       LDA ABSWS+&029A
       STA ABSWS+&02B7
       JSR LB9CA
.LB758 JSR L89D8
       JSR LB19C
.LB75E LDA #&00
       CMP ABSWS+&02B5
       LDX &C6
       LDY &C7
       RTS
;;
.LB768 JSR LB9CA
       LDA #&00
       SEC
       SBC ABSWS+&02B6
       STA ABSWS+&02B6
       CLC
       ADC ABSWS+&02B8
       STA ABSWS+&02B8
       BCC LB78A
       INC ABSWS+&02B9
       BNE LB78A
       INC ABSWS+&02BA
       BNE LB78A
       INC ABSWS+&02BB
.LB78A SEC
       LDA ABSWS+&0240
       SBC ABSWS+&02B6
       STA ABSWS+&0240
       BCS LB7A5
       LDY #&01
.LB798 LDA ABSWS+&0240,Y
       SBC #&00
       STA ABSWS+&0240,Y
       BCS LB7A5
       INY
       BNE LB798
.LB7A5 LDA ABSWS+&0241
       ORA ABSWS+&0242
       ORA ABSWS+&0243
       BNE LB7B3
       JMP LB82B
;;
.LB7B3 LDA #&01
       STA ABSWS+&0215
       LDY #&03
.LB7BA LDA ABSWS+&02B8,Y
       STA ABSWS+&0216,Y
       DEY
       BPL LB7BA
       LDA #&02
       CMP ABSWS+&02B4
       LDA #&02
       ROL A
       ROL A
       STA ABSWS+&021A
       LDX &CF
       LDA &C8
       CMP #&01
       LDA &C3CA,X
       ADC &C9
       STA ABSWS+&021D
       LDA ABSWS+&03C0,X
       ADC &CA
       STA ABSWS+&021C
       LDA ABSWS+&03B6,X
       ADC &CB
       STA ABSWS+&021B
       LDY #&04
.LB7EF LDA ABSWS+&0313,Y
       STA ABSWS+&022B,Y
       DEY
       BNE LB7EF
       STY ABSWS+&0317
       STY ABSWS+&021E
       STY ABSWS+&021F
       STY ABSWS+&0220
       CLC
       LDX #&02
.LB807 LDA ABSWS+&0241,Y
       STA ABSWS+&0221,Y
       ADC ABSWS+&02B9,Y
       STA ABSWS+&02B9,Y
       INY
       DEX
       BPL LB807
       JSR LAAB9
       JSR L8A42
       LDA ABSWS+&022F
       STA ABSWS+&0317
       LDA #&FF
       STA ABSWS+&022F
       STA ABSWS+&022E
.LB82B LDA ABSWS+&029A
       BNE LB833
       JMP LB758
;;
.LB833 LDX &CF
       CLC
       LDA ABSWS+&03CA,X
       ADC ABSWS+&029B
       STA ABSWS+&0296
       LDA ABSWS+&03C0,X
       ADC ABSWS+&029C
       STA ABSWS+&0297
       LDA ABSWS+&03B6,X
       ADC ABSWS+&029D
       STA ABSWS+&0298
       LDA #&02
       CMP ABSWS+&02B4
       LDA #&80
       ROR A
       JSR LABE7
       STZ ABSWS+&02B6
       LDA ABSWS+&029A
       STA ABSWS+&02B7
       JSR LB9CA
       JMP LB758
;;
.LB86B BIT &CD
       BPL LB898
       LDA ABSWS+&02BA
       LDX ABSWS+&02BB
       SHADOW_SELECT
       LDA ABSWS+&02BA
       CMP #&FE
       BCC LB885
       LDA ABSWS+&02BB
       INC A
       BEQ LB898
.LB885 PHP
       SEI
       JSR L8032
       LDA #&40
       TSB &CD
       LDA #&01
       LDX #&B8
       LDY #&C2
       JSR &0406
       PLP
.LB898 STZ &BD
       LDA ABSWS+&02B8
       STA &B2
       LDA ABSWS+&02B9
       STA &B3
       RTS
;;
.LB8A5 BIT &CD
       BVC LB8AD
       STA &FEE5
       RTS
;;
.LB8AD STY &BC
       LDY &BD
       STA (&B2),Y
       INC &BD
       BNE LB8B9
       INC &B3
.LB8B9 LDY &BC
       RTS
;;
.LB8BC LDA #&0A
       JSR LB8A5
       SEC
       LDX #&09
       LDY #&FF
.LB8C6 INY
       BCC LB8D3
       LDA (&B4),Y
       AND #&7F
       CMP #&21
       BCS LB8D3
       LDA #&20
.LB8D3 JSR LB8A5
       DEX
       BPL LB8C6
       RTS
;;
.LB8DA SBC #&05
       TAY
       BEQ LB8EB
       DEY
       BEQ LB92B
       DEY
       BEQ LB94F
       DEY
       BNE LB925
       JMP LB96A
;;
.LB8EB JSR LB86B
       LDY #&FF
.LB8F0 INY
       LDA ABSWS+&08D9,Y
       AND #&7F
       CMP #&20
       BCC LB8FE
       CPY #&13
       BNE LB8F0
.LB8FE TYA
       JSR LB8A5
       LDY #&FF
.LB904 INY
       LDA ABSWS+&08D9,Y
       AND #&7F
       CMP #&20
       BCC LB915
       JSR LB8A5
       CPY #&13
       BNE LB904
.LB915 LDA ABSWS+&01FD
       JSR LB8A5
       LDA ABSWS+&0317
       ASL A
       ROL A
       ROL A
       ROL A
       JSR LB8A5
.LB925 JSR L803A
       JMP LB75E
;;
.LB92B JSR LB86B
       LDA #&01
       JSR LB8A5
       LDA ABSWS+&0317
       JSR LB946
       LDA #<(ABSWS+&0300)
       STA &B4
       LDA #>(ABSWS+&0300)
       STA &B5
       JSR LB8BC
       BMI LB925
.LB946 ASL A
       ROL A
       ROL A
       ROL A
       ADC #&30
       JMP LB8A5
;;
.LB94F JSR LB86B
       LDA #&01
       JSR LB8A5
       LDA ABSWS+&031B
       JSR LB946
       LDA #<(ABSWS+&030A)
       STA &B4
       LDA #>(ABSWS+&030A)
       STA &B5
       JSR LB8BC
       BMI LB925
.LB96A JSR LB86B
       LDY #&00
       STY ABSWS+&02B5
       LDA ABSWS+&08FA
       STA (&C6),Y
       LDY #&05
       LDA (&C6),Y
       STA &B0
       BEQ LB925
       LDY #&09
       LDA (&C6),Y
       STA &B1
       CMP #&2F
       BCS LB925
       TAX
       CLC
       LDA #&05
       LDY #&C4
.LB98F DEX
       BMI LB99A
       ADC #&1A
       BCC LB98F
       INY
       CLC
       BCC LB98F
.LB99A STY &B5
       STA &B4
.LB99E LDY #&00
       LDA (&B4),Y
       STA ABSWS+&02B5
       BEQ LB9BB
       JSR LB8BC
       LDA &B4
       CLC
       ADC #&1A
       STA &B4
       BCC LB9B5
       INC &B5
.LB9B5 INC &B1
       DEC &B0
       BNE LB99E
.LB9BB LDY #&05
       LDA &B0
       STA (&C6),Y
       LDY #&09
       LDA &B1
       STA (&C6),Y
       JMP LB925
;;
.LB9CA LDA ABSWS+&02B6
       CMP ABSWS+&02B7
       BNE LB9D3
       RTS
;;
.LB9D3 BIT &CD
       BPL LBA03
       LDA ABSWS+&02BA
       LDX ABSWS+&02BB
       SHADOW_SELECT
       LDA ABSWS+&02BA
       CMP #&FE
       BCC LB9ED
       LDA ABSWS+&02BB
       INC A
       BEQ LBA03
.LB9ED LDA #&40
       TSB &CD
       JSR L8032
       LDA ABSWS+&02B4
       CMP #&03
       LDA #&00
       ROL A
       LDX #<(ABSWS+&02B8)
       LDY #>(ABSWS+&02B8)
       JSR &0406
.LBA03 LDA ABSWS+&02B8
       SEC
       SBC ABSWS+&02B6
       STA &B2
       LDA ABSWS+&02B9
       SBC #&00
       STA &B3
       LDA ABSWS+&02B4
       CMP #&03
       LDY ABSWS+&02B6
       PHP
.LBA1C PLP
       BIT &CD
       BVS LBA2F
       BCC LBA29
       LDA (&BE),Y
       STA (&B2),Y
       BCS LBA40
.LBA29 LDA (&B2),Y
       STA (&BE),Y
       BCC LBA40
.LBA2F JSR L821B
       BCC LBA3B
       LDA (&BE),Y
       STA &FEE5
       BCS LBA40
.LBA3B LDA &FEE5
       STA (&BE),Y
.LBA40 INY
       PHP
       CPY ABSWS+&02B7
       BNE LBA1C
       PLP
       JMP L803A
;;
IF INCLUDE_FLOPPY
;;
;;
;; ACCESS FLOPPY CONTROLLER
;; ========================
;;
;; Pass SCSI command to floppy controller
;; --------------------------------------
.LBA4B JMP LBB46        ;; Do a SCSI action with floppy drive
;;
.LBA4E JMP LBB57
;;
.LBA51 JMP LBA5D
;;
.LBA54 JMP LBA61
;;
ENDIF
.LBA57 LDA #&FF
       STA ABSWS+&02E4
       RTS
IF INCLUDE_FLOPPY
;;
.LBA5D LDA #&40
       BNE LBA63
.LBA61 LDA #&C0
.LBA63 STA ABSWS+&02E0
       TXA
       TSX
       STX ABSWS+&02E7
       PHA
       JSR LBBDE
       JSR LBBBE
       PLX
       BIT &A1
       BMI LBA83
       LDA &BC
       STA &0D0B
       LDA &BD
       STA &0D0C
       BNE LBA8D
.LBA83 LDA &BE
       STA &0D0E
       LDA &BF
       STA &0D0F
.LBA8D LDA ABSWS+&0203,X
       PHA
       AND #&1F
       BEQ LBA99
.LBA95 PLA
       JMP LBF6F
;;
.LBA99 PLA
       PHA
       AND #&40
       BNE LBA95
       PLA
       AND #&20
       BNE LBAA8
       LDA #&05
       BNE LBAAA
.LBAA8 LDA #&06
.LBAAA STA &0D5E
       LDA #&01
       TSB ABSWS+&02E4
       LDA ABSWS+&0201,X
       PHA
       LDA ABSWS+&0202,X
       TAX
       PLA
       LDY #&FF
       JSR LBFAB
       STA &A4
       STY &A5
       TYA
       SEC
       SBC #&50
       BMI LBACF
       STA &A5
       JSR LBD40
.LBACF LDA &0D5E
       STA &FE24        ;; Drive control register
       ROR A
       BCC LBAE4
       LDA ABSWS+&02E5
       STA &A3
       BIT ABSWS+&02E4
       BPL LBAF1
       BMI LBAEE
.LBAE4 LDA ABSWS+&02E6
       STA &A3
       BIT ABSWS+&02E4
       BVC LBAF1
.LBAEE JSR LBD55
.LBAF1 JSR LBAFA
       JSR LBD1E
       JMP LBFB7
;;
.LBAFA JSR LBD46
       LDX #&00
       JSR LBB3B
       INX
       JSR LBB3B
       INX
       JSR LBB3B
       CMP &A3
       BEQ LBB26
       LDA #&01
       TSB ABSWS+&02E4
       LDA #&14
       ORA &0D5C
       STA &FE28        ;; FDC Status/Command
       JSR LBCE5
       LDA &A1
       ROR A
       BCC LBB26
.LBB23 JMP LBFB7
;;
.LBB26 LDA &A5
       STA &A3
       BIT &A1
       BVS LBB38
       LDY #&05
       LDA (&B0),Y
       CMP #&0B
       BNE LBB38
       BEQ LBB23
.LBB38 JMP LBD46
;;
.LBB3B LDA &A3,X
.LBB3D STA &FE29,X      ;; Store in FDC Track/Sector
       CMP &FE29,X      ;; Keep storing until it stays there
       BNE LBB3D
       RTS
;;
;;
;; Access Floppy Disk Controller
;; -----------------------------
.LBB46 TSX
       STX ABSWS+&02E7  ;; Save stack pointer
       LDA #&10
       STA ABSWS+&02E0
       JSR LBB72
       JSR LBDBA
       BEQ LBB23
.LBB57 STA ABSWS+&02E2
       TSX
       STX ABSWS+&02E7
       LDA #>(ABSWS+&0215)
       STA &B1
       LDA #<(ABSWS+&0215)
       STA &B0
       STZ ABSWS+&02E0
       JSR LBB72
       JSR LBD6E
       JMP LBFB7
;;
.LBB72 STZ ABSWS+&02E3
       LDY #&01         ;; Point to address
       LDA (&B0),Y
       STA &B2
       INY
       LDA (&B0),Y
       STA &B3          ;; &B2/3=>Address low word
       INY
       LDA (&B0),Y      ;; Address byte 3
       TAX
       INY
       LDA (&B0),Y      ;; Address byte 4
       INX
       BEQ LBB8D
       INX
       BNE LBB91
.LBB8D CMP #&FF
       BEQ LBB98
.LBB91 BIT &CD
       BPL LBB98
       JSR L8020
.LBB98 LDY #&05
       LDA (&B0),Y      ;; Get command
       CMP #&08
       BEQ LBBB0        ;; Jump with Read
       CMP #&0A
       BEQ LBBB5        ;; Jump with Write
       CMP #&0B
       BEQ LBBB0        ;; Jump with Seek
       LDA #&67         ;; Floppy error &27 'Unsupported command'
       STA ABSWS+&02E3
       JMP LBFB7        ;; Jump to return with result=&67
;;
;; Read from floppy
;; ----------------
.LBBB0 LDA #&80
       TSB ABSWS+&02E0
;;
;; Write to floppy
;; ---------------
.LBBB5 JSR LBBDE
       JSR LBBBE
       JMP LBF0A
;;
.LBBBE JSR LBC01
       LDA ABSWS+&02E8
       STA &0D5C
       STZ &A0          ;; Clear error
       STZ &A2
       LDA ABSWS+&02E0        ;; b7=0=floppy write, 1=floppy read
       ORA #&20
       STA ABSWS+&02E0
       STA &A1
       LDA &CD
       STA &0D5D
       JSR LBC18
       RTS
;;
.LBBDE STZ &0D56
       STZ ABSWS+&02E8
       LDX #&0B
       LDA #&A1
       JSR &FFF4
       TYA
       PHA
       AND #&02
       BEQ LBBF6
       LDA #&03
       STA ABSWS+&02E8
.LBBF6 PLA
       AND #&01
       BEQ LBC00
       LDA #&02
       STA &0D56
.LBC00 RTS
;;
;; Claim NMI space
;; ---------------
.LBC01 LDA #&8F
       LDX #&0C
       LDY #&FF
       JSR &FFF4        ;; Claim NMI space
       STY ABSWS+&02E1  ;; Store previous owner's ID
       RTS
;;
;; Release NMI space
;; -----------------
.LBC0E LDY ABSWS+&02E1  ;; Get previous owner's ID
       LDA #&8F
       LDX #&0B
       JMP &FFF4        ;; Release NMI
;;
;; Copy NMI code to NMI space
;; --------------------------
.LBC18 LDY #&44
.LBC1A LDA LBCA0,Y
       STA &0D00,Y
       DEY
       BPL LBC1A
       LDY #&01
       LDA (&B0),Y
       STA &0D0E
       INY
       LDA (&B0),Y
       STA &0D0F
       BIT &A1
       BMI LBC39
       LDA #&5F
       STA &0D05
.LBC39 BIT &CD
       BVC LBC48
       LDA &A1
       AND #&FD
       STA &A1
       JSR LBC54
       BMI LBC4B
.LBC48 JSR LBC83
.LBC4B STA &0D5F
       LDA &F4
       STA &0D32
       RTS
;;
.LBC54 LDA &A1
       ROL A
       LDA #&00
       ROL A
       LDY #>(ABSWS+&0227)
       LDX #<(ABSWS+&0227)
       JSR &0406
       LDA &A1
       AND #&10
       BEQ LBC76
       BIT &A1
       BMI LBC77
       LDY #&07
.LBC6D LDA LBD0E,Y
       STA &0D0A,Y
       DEY
       BPL LBC6D
.LBC76 RTS
;;
.LBC77 LDY #&07
.LBC79 LDA LBD16,Y
       STA &0D0A,Y
       DEY
       BPL LBC79
       RTS
;;
.LBC83 BIT &A1
       BMI LBC9F
       LDY #&0D
.LBC89 LDA LBD00,Y
       STA &0D0A,Y
       DEY
       BPL LBC89
       LDY #&01
       LDA (&B0),Y
       STA &0D0B
       INY
       LDA (&B0),Y
       STA &0D0C
.LBC9F RTS
;;
;; NMI code, copied to &0D00
;; -------------------------
.LBCA0 PHA
       LDA &FE28        ;; FDC Status/Command
       AND #&1F
       CMP #&03
       BNE LBCBA
       LDA &FE2B        ;; FDC Data
       STA &FFFF        ;; Replaced with destination address
       INC &0D0E
       BNE LBCB8
       INC &0D0F
.LBCB8 PLA
       RTI
;;
.LBCBA AND #&58         ;; Check b3, b4, b6 (CRC, Not Found, Write Prot)
       BEQ LBCCA        ;; No error
       STA &A0          ;; Store as floppy error
       LDA #&01
       TSB &A1
.LBCC4 LDA #&01
       TSB &A2
       PLA
       RTI
;;
.LBCCA BIT &A2
       BVC LBCC4
       LDA &F4
       PHA
       LDA #&00
       STA &F4
       STA &FE30
       PHX
       JSR LBE77
       PLX
       PLA
       STA &F4
       STA &FE30
       PLA
       RTI
;;
.LBCE5 LDA &A2
       ROR A
       BCC LBCEB
       RTS
;;
.LBCEB LDA &0D5D
       AND #&10
       BEQ LBCE5
       BIT &FF
       BPL LBCE5
       STZ &FE24        ;; Drive control
       LDA #&6F         ;; Floppy error &2F (Abort)
       STA &A0
       JMP LBFB7
;;
.LBD00 LDA &FFFF
       STA &FE2B        ;; FDC Data register
       INC &0D0B
       BNE LBD0E
       INC &0D0C
.LBD0E LDA &FEE5
       STA &FE2B        ;; FDC Data register
       BCS LBD1C
.LBD16 LDA &FE2B        ;; FDC Data register
       STA &FEE5
.LBD1C BCS LBD24
.LBD1E BIT &A1
       BMI LBD2F
       LDA &A3
.LBD24 CMP #&14
       LDA #&A0
       BCC LBD31
       ORA &0D56
       BNE LBD31
.LBD2F LDA #&80
.LBD31 JSR LBD62
       STA &FE28        ;; FDC Status/Command
       JMP LBCE5
;;
       LDA #&10
       TRB &0D5E        ;; Set side 0
       RTS
;;
.LBD40 LDA #&10
       TSB &0D5E        ;; Set side 1
       RTS
;;
.LBD46 LDA #&01
       TRB &A2
       RTS
;;
.LBD4B LDA #&08
       TRB &A2
       RTS
;;
.LBD50 LDA #&02
       TRB &A2
       RTS
;;
.LBD55 LDA #&00
       STA &A3
       ORA &0D5C
       STA &FE28        ;; FDC Status/Command
       JMP LBCE5
;;
.LBD62 ROR ABSWS+&02E4
       BCC LBD6A
       ORA #&04
       CLC
.LBD6A ROL ABSWS+&02E4
       RTS
;;
.LBD6E LDA ABSWS+&02E2
       STA &0D0F
       STZ &0D0E
       JSR LBAFA
       JSR LBD1E
       LDA &A3
       PHA
       LDA ABSWS+&0216
       STA &A5
       LDA ABSWS+&0217
       STA &A6
       LDA #&00
       STA &A3
       LDA ABSWS+&02E2
       STA &A4
       BIT &CD
       BVC LBDAB
       LDY #&00
.LBD99 LDA (&A3),Y
       LDX #&07
.LBD9D DEX
       BNE LBD9D
       STA &FEE5
       INY
       CPY ABSWS+&021E
       BNE LBD99
       BEQ LBDB6
.LBDAB LDY ABSWS+&021E
.LBDAE DEY
       LDA (&A3),Y
       STA (&A5),Y
       TYA
       BNE LBDAE
.LBDB6 PLA
       STA &A3
       RTS
;;
.LBDBA JSR LBAFA
       LDA #&40
       TSB &A2
       LDY #&07
       LDA (&B0),Y
       STA &0D58
       INY
       LDA (&B0),Y
       INY
       CLC
       ADC (&B0),Y
       STA &0D59
       BCC LBDD7
       INC &0D58
.LBDD7 LDA &0D58
       TAX
       LDA &0D59
       LDY #&FF
       JSR LBFAB
       CMP #&00
       BNE LBDE9
       LDA #&10
.LBDE9 LDY #&09
       SEC
       SBC (&B0),Y
       BCS LBE0D
       LDA #&10
       SEC
       SBC &A4
       STA &0D58
       LDA (&B0),Y
       SEC
       SBC &0D58
       LDX #&00
       LDY #&FF
       JSR LBFAB
       STY &0D57
       STA &0D59
       BPL LBE1C
.LBE0D LDY #&09
       LDA (&B0),Y
       STA &0D58
       LDA #&FF
       STA &0D57
       STZ &0D59
.LBE1C STZ &0D5A
       INC &0D57
       DEC &0D58
       LDX #&01
       JSR LBB3B
       BIT &A1
       BMI LBE35
       LDA #&A0
       ORA &0D56
       BNE LBE37
.LBE35 LDA #&80
.LBE37 STA &A6
       JSR LBD46
       LDA &A6
       STA &FE28        ;; FDC Status/Command
.LBE41 JSR LBCE5
       LDA &A2
       AND #&02
       BEQ LBE5C
       JSR LBD46
       JSR LBD50
       LDA #&54
       ORA &0D5C
       STA &FE28        ;; FDC Status/Command
       INC &A3
       BNE LBE41
.LBE5C LDA &A2
       AND #&08
       BEQ LBE90
       JSR LBD46
       JSR LBD4B
       INC &A3
       JSR LBD40
       LDA #&00
       ORA &0D5C
       STA &FE28        ;; FDC Status/Command
       BPL LBE41
;;
;; NMI Routine - called from &0D00
;; ===============================
.LBE77 JSR LBD46
       JSR LBE91
       TXA
       BNE LBE85
       LDA #&01
       TSB &A2
       RTS
;;
.LBE85 JSR LBD50
       LDA &A6
       JSR LBD62
       STA &FE28        ;; FDC Status/Command
.LBE90 RTS
;;
.LBE91 LDA &0D58
       BNE LBEF8
       LDA &0D57
       BNE LBEAA
       LDA &0D59
       BNE LBEA4
       LDX #&00
       BEQ LBF09
.LBEA4 DEC &0D59
       JMP LBEFB
;;
.LBEAA LDA &0D5A
       BNE LBEF2
       LDA #&01
       TSB ABSWS+&02E4
       LDA &FE29        ;; FDC Track register
       CMP #&4F
       BCC LBEDA        ;; Less than 80
       LDA &0D5E
       AND #&10
       BEQ LBEC7
       LDX #&00
       JMP LBEFD
;;
.LBEC7 LDA #&FF
       STA &A3
       JSR LBD40
       LDA &0D5E
       STA &FE24        ;; Drive control
       LDA &A2
       ORA #&08
       BNE LBEDE
.LBEDA LDA &A2
       ORA #&02
.LBEDE STA &A2
       DEC &0D57
       BEQ LBEEA
       LDA #&10
       STA &0D5A
.LBEEA LDA #&FE
       STA &A4
       LDX #&00
       BEQ LBEFD
.LBEF2 DEC &0D5A
       JMP LBEFB
;;
.LBEF8 DEC &0D58
.LBEFB LDX #&FF
.LBEFD INC &A4
.LBEFF LDA &A4
       STA &FE2A        ;; FDC Sector register
       CMP &FE2A        ;; Keep storing until it stays there
       BNE LBEFF
.LBF09 RTS
;;
;;   &A0  Returned error, &40+FDC status or &40+scsi error
;;   &A1  b7=write/read, b5=??, b0=error occured?
;;   &A2  b0=?
;;   &A3
;;   &A4 sector
;;   &A5 track
;;   &A6 drive
;;   &A7
;;
.LBF0A LDY #&06
       LDA (&B0),Y      ;; Get drive
       ORA ABSWS+&0317        ;; OR with current drive
       STA &A6          ;; Store drive in &A6
       AND #&1F         ;; Lose drive bits
       BEQ LBF1A
       JMP LBF6F        ;; If sector>&FFFF, jump to 'Sector out of range'
;;
.LBF1A BIT &A6          ;; Check drive
       BVC LBF24        ;; Drive 0,1,4,5 -> jump ahead
;;                                         Can patch here to support drive 2,3,6,7
       LDA #&65         ;; Otherwise, floppy error &25 (Bad drive)
       STA &A0          ;; Set error
       BNE LBF73        ;; Jump to return error
;;
;; Drive 0,1,4,5
;; -------------
.LBF24 LDA &A6          ;; Get drive
       AND #&20
       BNE LBF2E        ;; Drive 1,5 -> jump ahead
       LDA #&05         ;; Drive 0,4 -> &05=RES+DS0
       BNE LBF30
.LBF2E LDA #&06         ;; Drive 1,5 -> &06=RES+DS1
.LBF30 STA &0D5E        ;; Store drive control byte
       LDA #&01
       TSB ABSWS+&02E4
       JSR LBF5E        ;; Calculate sector/track
       LDA &0D5E        ;; Get drive control byte
       STA &FE24        ;; Set drive control register
       ROR A            ;; Rotate drive 1 bit into carry
       BCC LBF50        ;; Jump if drive 0
       LDA ABSWS+&02E5
       STA &A3
       BIT ABSWS+&02E4
       BPL LBF5D
       BMI LBF5A
;;
.LBF50 LDA ABSWS+&02E6
       STA &A3
       BIT ABSWS+&02E4
       BVC LBF5D
.LBF5A JSR LBD55
.LBF5D RTS
;;
.LBF5E LDY #&07
       LDA (&B0),Y      ;; Get sector b8-b15
       CMP #&0A         ;; Check for sector &0A00
       BCC LBF8F        ;; <&A00 - sector within range
;;                                         Bug, the rest of these checks shouldn't happen
;;                                         Should just drop straight into 'Sector out of range'
       BNE LBF6F        ;; >&AFF - sector out of range
       INY              ;; Check sector &0Axx for some reason
       LDA (&B0),Y      ;; Get sector b0-b7
       CMP #&00         ;; Sector &A00?
       BCC LBF75        ;; Will never follow this jump - should this be BEQ ?
.LBF6F LDA #&61         ;; Floppy error &21 (Bad address)
       STA &A0
;;
;; Jump to return floppy error
;; ---------------------------
.LBF73 BNE LBFB7        ;; Jump to return error in &A0
;;
;; This code never entered, as the above BCC LBF75 never followed
.LBF75 LDA &A1          ;; Get flag
       AND #&10
       BEQ LBF8F        ;; If b3=0, do it anyway
       LDY #&09
       LDA (&B0),Y      ;; Get count
       DEY              ;; Point to sector b0-b7
       CLC
       ADC (&B0),Y      ;; A=sector.b0-7 + count
       BCS LBF89        ;; >255, jump to volume error
       CMP #&01
       BCC LBF8F        ;; sector+count<1 - do it
.LBF89 LDA #&63         ;; Floppy error &23 (Volume error)
       STA &A0
       BNE LBFB7        ;; Jump to return error
;;
.LBF8F LDY #&07
       LDA (&B0),Y      ;; Get sector b8-b15
       TAX              ;; Pass to X
       INY
       LDA (&B0),Y      ;; Get sector b0-b7
       LDY #&FF
       JSR LBFAB        ;; Divide by 16
       STA &A4          ;; A=sector
       STY &A5          ;; Y=track 0-159
       TYA
       SEC
       SBC #&50         ;; Track <80?
       BMI LBFB6        ;; Side 0, leave track as 0-79
       STA &A5          ;; Store track 0-79
       JMP LBD40        ;; Set side 1
;;
;; Divide by 16
;; ============
;; On entry: A=low byte
;;           X=high byte
;;           Y=&FF
;; On exit:  Y=&XA DIV 16
;;           A=&XA MOD 16
.LBFAB SEC
       SBC #&10
       INY
       BCS LBFAB
       DEX
       BPL LBFAB
       ADC #&10
.LBFB6 RTS
;;
;; Drive 2,3,6,7
;; -------------
.LBFB7 LDX ABSWS+&02E7
       TXS              ;; Reset stack
       LDA ABSWS+&02E0
       AND #&20
       BEQ LBFE9        ;; b6=0, jump to release and return
       LDA &0D5E        ;; Get drive control byte
       ROR A            ;; Cy=0 drv1/5, Cy=1 drv0/4
       LDA &A3
       BCC LBFD6        ;; Jump if drive 1/5
       STA ABSWS+&02E5  ;; Store
       ROL ABSWS+&02E4
       CLC
       ROR ABSWS+&02E4  ;; Clear b7
       BCS LBFE1
;;
.LBFD6 STA ABSWS+&02E6
       LDA ABSWS+&02E4
       AND #&BF
       STA ABSWS+&02E4  ;; Clear b6
;;
.LBFE1 LDA &A0          ;; Get error
       STA ABSWS+&02E3  ;; Store in error block
       JSR LBC0E        ;; Release NMI
.LBFE9 JSR L803A        ;; Release Tube, restore screen
       LDX &B0
       LDA ABSWS+&02E3        ;; Get error
       BEQ LBFFA        ;; If zero, jump to return Ok
       ORA #&40         ;; Set bit 6 to flag FDC error
       LDY #&FF
       STY ABSWS+&02E4
.LBFFA LDY &B1
       AND #&7F         ;; Remove bit 7 and set EQ
       RTS              ;; Return with A=error, EQ=Ok
;;
IF NOT(TEST_SHIFT)
       EQUB &A9
ENDIF

ENDIF

;; This is cludge, need to check this is really not used in IDE Mode
IF PATCH_IDE OR PATCH_SD
L81AD=CommandDone
ENDIF

IF PATCH_SD
include "MMC.asm"
include "MMC_UserPort.asm"
ENDIF

PRINT "    code ends at",~P%," (",(&C000 - P%), "bytes free )"

SAVE "", &8000, &C000
