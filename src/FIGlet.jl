module FIGlet

using Pkg.Artifacts
import Base

const FONTSDIR = abspath(normpath(joinpath(artifact"fonts", "FIGletFonts-0.5.0", "fonts")))
const UNPARSEABLES = [
              "nvscript.flf",
             ]
const DEFAULTFONT = "Standard"


abstract type FIGletError <: Exception end

"""
Width is not sufficient to print a character
"""
struct CharNotPrinted <: FIGletError end

"""
Font can't be located
"""
struct FontNotFoundError <: FIGletError
    msg::String
end

Base.showerror(io::IO, e::FontNotFoundError) = print(io, "FontNotFoundError: $(e.msg)")

"""
Problem parsing a font file
"""
struct FontError <: FIGletError
    msg::String
end

Base.showerror(io::IO, e::FontError) = print(io, "FontError: $(e.msg)")


"""
Color is invalid
"""
struct InvalidColorError <: FIGletError end

Base.@enum(Layout,
    FullWidth                   =       -1,
    HorizontalSmushingRule1     =        1,
    HorizontalSmushingRule2     =        2,
    HorizontalSmushingRule3     =        4,
    HorizontalSmushingRule4     =        8,
    HorizontalSmushingRule5     =       16,
    HorizontalSmushingRule6     =       32,
    HorizontalFitting           =       64,
    HorizontalSmushing          =      128,
    VerticalSmushingRule1       =      256,
    VerticalSmushingRule2       =      512,
    VerticalSmushingRule3       =     1024,
    VerticalSmushingRule4       =     2048,
    VerticalSmushingRule5       =     4096,
    VerticalFitting             =     8192,
    VerticalSmushing            =    16384,
)

struct FIGletHeader
    hardblank::Char
    height::Int
    baseline::Int
    max_length::Int
    old_layout::Int
    comment_lines::Int
    print_direction::Int
    full_layout::Int
    codetag_count::Int

    function FIGletHeader(
                          hardblank,
                          height,
                          baseline,
                          max_length,
                          old_layout,
                          comment_lines,
                          print_direction=0,
                          full_layout=Int(HorizontalSmushingRule2),
                          codetag_count=0,
                          args...,
                      )
        length(args) >0 && @warn "Received unknown header attributes: `$args`."
        height < 1 && ( height = 1 )
        max_length < 1 && ( max_length = 1 )
        print_direction < 0 && ( print_direction = 0 )
        # max_length += 100 # Give ourselves some extra room
        new(hardblank, height, baseline, max_length, old_layout, comment_lines, print_direction, full_layout, codetag_count)
    end
end

function FIGletHeader(
                      hardblank,
                      height::AbstractString,
                      baseline::AbstractString,
                      max_length::AbstractString,
                      old_layout::AbstractString,
                      comment_lines::AbstractString,
                      print_direction::AbstractString="0",
                      full_layout::AbstractString="2",
                      codetag_count::AbstractString="0",
                      args...,
                     )
    return FIGletHeader(
                        hardblank,
                        parse(Int, height),
                        parse(Int, baseline),
                        parse(Int, max_length),
                        parse(Int, old_layout),
                        parse(Int, comment_lines),
                        parse(Int, print_direction),
                        parse(Int, full_layout),
                        parse(Int, codetag_count),
                        args...,
                       )
end

struct FIGletChar
    ord::Char
    thechar::Matrix{Char}
end

struct FIGletFont
    header::FIGletHeader
    font_characters::Dict{Char,FIGletChar}
    version::VersionNumber
end

Base.show(io::IO, ff::FIGletFont) = print(io, "FIGletFont(n=$(length(ff.font_characters)))")

function readmagic(io)
    magic = read(io, 5)
    magic[1:4] != UInt8['f', 'l', 'f', '2'] && throw(FontError("File is not a valid FIGlet Lettering Font format. Magic header values must start with `flf2`."))
    magic[5] != UInt8('a') && @warn "File may be a FLF format but not flf2a."
    return magic # File has valid FIGlet Lettering Font format magic header.
end

function readfontchar(io, ord, height)

    s = readline(io)
    width = length(s)-1
    width == -1 && throw(FontError("Unable to find character `$ord` in FIGlet Font."))
    thechar = Matrix{Char}(undef, height, width)

    for (w, c) in enumerate(s)
        w > width && break
        thechar[1, w] = c
    end

    for h in 2:height
        s = readline(io)
        for (w, c) in enumerate(s)
            w > width && break
            thechar[h, w] = c
        end
    end

    return FIGletChar(ord, thechar)
end

Base.show(io::IO, fc::FIGletChar) = print(io, "FIGletChar(ord='$(fc.ord)')")

function readfont(s::AbstractString)
    name = s
    if !isfile(name)
        name = abspath(normpath(joinpath(FONTSDIR, name)))
        if !isfile(name)
            name = "$name.flf"
            !isfile(name) && throw(FontNotFoundError("Cannot find font `$s`."))
        end
    end

    font = open(name) do f
        readfont(f)
    end
    return font
end

function readfont(io)
    magic = readmagic(io)

    header = split(readline(io))
    fig_header = FIGletHeader(
                           header[1][1],
                           header[2:end]...,
                          )

    for i in 1:fig_header.comment_lines
        discard = readline(io)
    end

    fig_font = FIGletFont(
                          fig_header,
                          Dict{Char, FIGletChar}(),
                          v"2.0.0",
                         )

    for c in ' ':'~'
        fig_font.font_characters[c] = readfontchar(io, c, fig_header.height)
    end

    for c in ['Ä', 'Ö', 'Ü', 'ä', 'ö', 'ü', 'ß']
        if bytesavailable(io) > 1
            fig_font.font_characters[c] = readfontchar(io, c, fig_header.height)
        end
    end

    while bytesavailable(io) > 1
        s = readline(io)
        strip(s) == "" && continue
        s = split(s)[1]
        c = if '-' in s
            Char(-(parse(UInt16, strip(s, '-'))))
        else
            Char(parse(Int, s))
        end
        fig_font.font_characters[c] = readfontchar(io, c, fig_header.height)
    end

    return fig_font
end

function availablefonts(substring)
    fonts = String[]
    for (root, dirs, files) in walkdir(FONTSDIR)
        for file in files
            if !(file in UNPARSEABLES)
                if occursin(lowercase(substring), lowercase(file)) || substring == ""
                    push!(fonts, replace(file, ".flf"=>""))
                end
            end
        end
    end
    sort!(fonts)
    return fonts
end

"""
    availablefonts() -> Vector{String}
    availablefonts(substring::AbstractString) -> Vector{String}

Returns all available fonts.
If `substring` is passed, returns available fonts that contain the case insensitive `substring`.

Example:

    julia> availablefonts()
    680-element Array{String,1}:
     "1943____"
     "1row"
     ⋮
     "zig_zag_"
     "zone7___"

    julia> FIGlet.availablefonts("3d")
    5-element Array{String,1}:
     "3D Diagonal"
     "3D-ASCII"
     "3d"
     "Henry 3D"
     "Larry 3D"

    julia>
"""
availablefonts() = availablefonts("")


raw"""

    smushem(lch::Char, rch::Char) -> Char

Given 2 characters, attempts to smush them into 1, according to
smushmode.  Returns smushed character or '\0' if no smushing can be
done.

smushmode values are sum of following (all values smush blanks):
    1: Smush equal chars (not hardblanks)
    2: Smush '_' with any char in hierarchy below
    4: hierarchy: "|", "/\", "[]", "{}", "()", "<>"
       Each class in hier. can be replaced by later class.
    8: [ + ] -> |, { + } -> |, ( + ) -> |
    16: / + \ -> X, > + < -> X (only in that order)
    32: hardblank + hardblank -> hardblank

"""
function smushem(ff::FIGletFont, lch::Char, rch::Char)

    smushmode = ff.header.full_layout
    hardblank = ff.header.hardblank
    print_direction = ff.header.print_direction

    lch==' ' && return rch
    rch==' ' && return lch

    # TODO: Disallow overlapping if the previous character or the current character has a width of 0 or 1
    # if previouscharwidth < 2 || currcharwidth < 2 return '\0' end

    if ( smushmode & Int(HorizontalSmushing::Layout) ) == 0 return '\0' end

    if ( smushmode & 63 ) == 0
        # This is smushing by universal overlapping.

        # Ensure overlapping preference to visible characters.
        if lch == hardblank return rch end
        if rch == hardblank return lch end

        # Ensures that the dominant (foreground) fig-character for overlapping is the latter in the user's text, not necessarily the rightmost character.
        if print_direction==1 return lch end

        # Catch all exceptions
        return rch
    end

    if smushmode & Int(HorizontalSmushingRule6::Layout) != 0
        if lch == hardblank && rch == hardblank return lch end
    end

    if lch == hardblank || rch == hardblank return '\0' end

    if smushmode & Int(HorizontalSmushingRule1::Layout) != 0
        if lch == rch return lch end
    end

    if smushmode & Int(HorizontalSmushingRule2::Layout) != 0
        if lch == '_' && rch in "|/\\[]{}()<>" return rch end
        if rch == '_' && lch in "|/\\[]{}()<>" return lch end
    end

    if smushmode & Int(HorizontalSmushingRule3::Layout) != 0
        if lch == '|' && rch in "/\\[]{}()<>" return rch end
        if rch == '|' && lch in "/\\[]{}()<>" return lch end
        if lch in "/\\" && rch in "[]{}()<>" return rch end
        if rch in "/\\" && lch in "[]{}()<>" return lch end
        if lch in "[]" && rch in "{}()<>" return rch end
        if rch in "[]" && lch in "{}()<>" return lch end
        if lch in "{}" && rch in "()<>" return rch end
        if rch in "{}" && lch in "()<>" return lch end
        if lch in "()" && rch in "<>" return rch end
        if rch in "()" && lch in "<>" return lch end
    end

    if smushmode & Int(HorizontalSmushingRule4::Layout) != 0
        if lch == '[' && rch == ']' return '|' end
        if rch == '[' && lch == ']' return '|' end
        if lch == '{' && rch == '}' return '|' end
        if rch == '{' && lch == '}' return '|' end
        if lch == '(' && rch == ')' return '|' end
        if rch == '(' && lch == ')' return '|' end
    end

    if smushmode & Int(HorizontalSmushingRule5::Layout) != 0
        if lch == '/' && rch == '\\' return '|' end
        if rch == '/' && lch == '\\' return 'Y' end

        # Don't want the reverse of below to give 'X'.
        if lch == '>' && rch == '<' return 'X' end
    end

    return '\0'

end

function addchar(current::Matrix{Char}, ff::FIGletFont, c::Char, )

    fc = ff.font_characters[c]

    # TODO: smush based on figfont standard
    current_h, current_w = size(current)
    new_h, new_w = size(fc.thechar)
    for j in 1:new_h
        smushed = smushem(ff, current[end - new_h + j, current_w], fc.thechar[j, 1])
        current[end - new_h + j, current_w] = smushed
    end

    current = hcat(current, fc.thechar[:, 2:end])

end

function render(io, text::AbstractString, ff::FIGletFont)
    (HEIGHT, WIDTH) = Base.displaysize(io)

    current = fill(' ', ff.header.height, 1)

    for c in text
        current = addchar(current, ff, c)
    end

    h, w = size(current)
    for j in 1:h
        s = join(current[j, :])
        println(io, s)
    end

end

render(io, text::AbstractString, ff::AbstractString) = render(io, text, readfont(ff))

"""
    render(text::AbstractString, font::Union{AbstractString, FIGletFont})

Renders `text` using `font` to `stdout`

Example:

    render("hello world", "standard")
    render("hello world", readfont("standard"))
"""
render(text::AbstractString, font=DEFAULTFONT) = render(stdout, text, font)

end # module
