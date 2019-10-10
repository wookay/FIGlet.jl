module FIGlet

const DEFAULT_FONT = "standard"

Base.@enum COLOR_CODES BLACK=30 RED=31 GREEN=32 YELLOW=33 BLUE=34 MAGENTA=35 CYAN=36 LIGHT_GRAY=37 DEFAULT=39 DARK_GRAY=90 LIGHT_RED=91 LIGHT_GREEN=92 LIGHT_YELLOW= 93 LIGHT_BLUE= 94 LIGHT_MAGENTA=95 LIGHT_CYAN=96 WHITE=97 RESET=0

const RESET_COLORS = "\033[0m"

const SHARED_DIRECTORY = "figlet"

const FONTFILESUFFIX = ".flf"
const FONTFILEMAGICNUMBER = "flf2"


abstract type FIGletError <: Exception end

"""
Width is not sufficient to print a character
"""
struct CharNotPrinted <: FIGletError end

"""
Font can't be located
"""
struct FontNotFound <: FIGletError end


"""
Problem parsing a font file
"""
struct FontError <: FIGletError end


"""
Color is invalid
"""
struct InvalidColor <: FIGletError end


end # module
