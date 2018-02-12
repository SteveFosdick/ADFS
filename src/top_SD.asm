PATCH_IDE=FALSE
PATCH_SD=TRUE
PATCH_FULL_ACCESS=TRUE
PATCH_INFO=TRUE
PATCH_UNSUPPORTED_OSFILE=TRUE
PATCH_PRESERVE_CONTEXT=TRUE
TEST_SHIFT=FALSE
INCLUDE_FLOPPY=FALSE
SHADOW_SCREEN=TRUE
COMMON_COMMANDS=FALSE

ABSWS=&C000
        
;;; Used in the SD Build only
_VIA_BASE=&FE60                 ; Base Address of 6522 VIA
_TUBE_BASE=&FEE0                ; Base Address of Tube
_TURBOMMC=0                     ; 1 = build for TurboMMC, and enable PB2-4 as outputs

TUBE_R3_DATA        = _TUBE_BASE + &05

MAX_DRIVES          = 2         ; don't make this bigger than 2 or the drive table below will overflow

attempts%           = ABSWS+&02E9 ; 1 byte
sectorcount%        = ABSWS+&02EA ; 1 byte
cardsort%           = ABSWS+&02EB ; 1 byte
mmcstate%           = ABSWS+&02EC ; 1 byte
numdrives%          = ABSWS+&02ED ; 1 byte
cmdseq%             = ABSWS+&02F0 ; 8 bytes
drivetable%         = ABSWS+&02F8 ; 4 * MAX_DRIVES

mbrsector%          = ABSWS     ; 512 bytes tmp storage before fs is mounted
        
datptr%             = &B2

EscapeFlag          = &FF

include "adfs150.asm"
