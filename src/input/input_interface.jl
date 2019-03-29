Base.include(@__MODULE__, "../../input.jl")

#------------------------------#
#          JuliChem.jl         #
#------------------------------#
"""
     do_input(file::String)
Summary
======
Read in input file.

Arguments
======
file = name of input file to read in
"""
function do_input(file::String)
    #read in .inp and .dat files
    println("========================================")
    println("         READING INPUT DATA FILE        ")
    println("========================================")
    dat::Array{String,1} = process_data_file(file)
    println("========================================")
    println("                END INPUT               ")
    println("========================================")
    println("")

    #do file processing
    #println("Processing input file...")
    coord::Array{Float64,2} = input_geometry()

    return dat
end

function input_flags()
    CTRL::Ctrl_Flags = input_ctrl_flags()
    BASIS::Basis_Flags = input_basis_flags()
    HF::HF_Flags = input_hf_flags()

    FLAGS::Flags = Flags(CTRL,BASIS,HF)
    return FLAGS
end
