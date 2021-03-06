function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    isdefined(Base, Symbol("#@threads")) && precompile(Tuple{getfield(Base.Threads, Symbol("#@threads")), LineNumberNode, Module, Int})
    isdefined(Base, Symbol("#@views")) && precompile(Tuple{getfield(Base, Symbol("#@views")), LineNumberNode, Module, Int})
    precompile(Tuple{typeof(Base.Broadcast._broadcast_getindex_evalf), typeof(Base._views), Expr})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!), Array{Expr, 1}, Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, typeof(Base._views), Tuple{Base.Broadcast.Extruded{Array{Any, 1}, Tuple{Bool}, Tuple{Int64}}}}, Base.OneTo{Int64}, Int64, Int64})
    precompile(Tuple{typeof(Base.Broadcast.copyto_nonleaf!), Array{Symbol, 1}, Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, typeof(Base._views), Tuple{Base.Broadcast.Extruded{Array{Any, 1}, Tuple{Bool}, Tuple{Int64}}}}, Base.OneTo{Int64}, Int64, Int64})
    precompile(Tuple{typeof(Base.Broadcast.instantiate), Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Nothing, typeof(Base._views), Tuple{Array{Any, 1}}}})
    precompile(Tuple{typeof(Base.Broadcast.restart_copyto_nonleaf!), Array{Any, 1}, Array{Expr, 1}, Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, typeof(Base._views), Tuple{Base.Broadcast.Extruded{Array{Any, 1}, Tuple{Bool}, Tuple{Int64}}}}, Int64, Int64, Base.OneTo{Int64}, Int64, Int64})
    precompile(Tuple{typeof(Base.Broadcast.restart_copyto_nonleaf!), Array{Any, 1}, Array{Symbol, 1}, Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, typeof(Base._views), Tuple{Base.Broadcast.Extruded{Array{Any, 1}, Tuple{Bool}, Tuple{Int64}}}}, Expr, Int64, Base.OneTo{Int64}, Int64, Int64})
    precompile(Tuple{typeof(Base.Broadcast.restart_copyto_nonleaf!), Array{Any, 1}, Array{Symbol, 1}, Base.Broadcast.Broadcasted{Base.Broadcast.DefaultArrayStyle{1}, Tuple{Base.OneTo{Int64}}, typeof(Base._views), Tuple{Base.Broadcast.Extruded{Array{Any, 1}, Tuple{Bool}, Tuple{Int64}}}}, Int64, Int64, Base.OneTo{Int64}, Int64, Int64})
    precompile(Tuple{typeof(Base.Docs.docm), LineNumberNode, Module, Int, Int})
    precompile(Tuple{typeof(Base.Docs.docstr), Int, Int})
    precompile(Tuple{typeof(Base.Docs.moduledoc), Int, Int, Int, Int, Expr})
    precompile(Tuple{typeof(Base.Docs.objectdoc), Int, Int, Int, Int, Int, Int})
    precompile(Tuple{typeof(Base.MainInclude.include), String})
    precompile(Tuple{typeof(Base.Threads._threadsfor), Expr, Expr, Symbol})
    precompile(Tuple{typeof(Base.Threads.resize_nthreads!), Array{Base.MPFR.BigFloat, 1}, Base.MPFR.BigFloat})
    precompile(Tuple{typeof(Base._views), Expr})
    precompile(Tuple{typeof(Base.hashindex), Tuple{Int64, Int32, UInt64}, Int64})
    precompile(Tuple{typeof(Base.hashindex), Tuple{Int64, Nothing, UInt64}, Int64})
    precompile(Tuple{typeof(Base.ht_keyindex), Base.Dict{Base.PkgId, Array{Function, 1}}, Base.PkgId})
    precompile(Tuple{typeof(Base.hvcat), Tuple{Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64, Int64}, Float64, Float64})
    precompile(Tuple{typeof(Base.isassigned), Core.SimpleVector, Int64})
    precompile(Tuple{typeof(Base.push!), Array{Function, 1}, typeof(identity)})
    precompile(Tuple{typeof(Base.rehash!), Base.Dict{Int64, Tuple{Function, Int64, Vararg{Int64, N} where N}}, Int64})
    precompile(Tuple{typeof(Base.rehash!), Base.Dict{String, Tuple{Any, Any, Int64}}, Int64})
    precompile(Tuple{typeof(Base.rehash!), Base.Dict{Tuple{Int64, Any, UInt64}, DataType}, Int64})
    precompile(Tuple{typeof(Base.require), Module, Symbol})
    precompile(Tuple{typeof(Base.setindex!), Base.Dict{Pkg.BinaryPlatforms.Platform, Base.Dict{String, Any}}, Base.Dict{String, Any}, Pkg.BinaryPlatforms.FreeBSD})
    precompile(Tuple{typeof(Base.sqrt), Float64})
end
