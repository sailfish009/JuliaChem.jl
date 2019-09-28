using MATH
using JCModules.Globals

using MPI
using Base.Threads
#using Distributed
using LinearAlgebra
using JLD

function rhf_energy(basis::BasisStructs.Basis,
  molecule::Union{Dict{String,Any},Dict{Any,Any}},
  scf_flags::Dict{String,Any})

  if (scf_flags["prec"] == "Float64")
    return rhf_kernel(basis,molecule,scf_flags,oneunit(Float64))
  elseif (scf_flags["prec"] == "Float32")
    return rhf_kernel(basis,molecule,scf_flags,oneunit(Float32))
  end
end


"""
	 rhf_kernel(FLAGS::RHF_Flags, basis::Basis, read_in::Dict{String,Any},
       type::T)
Summary
======
Perform the core RHF SCF algorithm.

Arguments
======
FLAGS = Input flags

basis = Generated basis set

read_in = file required to read in from input file

type = Precision of variables in calculation
"""
function rhf_kernel(basis::BasisStructs.Basis,
  molecule::Union{Dict{String,Any},Dict{Any,Any}},
  scf_flags::Dict{String,Any}, type::T) where {T<:AbstractFloat}

  comm=MPI.COMM_WORLD
  calculation_status::Dict{String,Any} = Dict([])

  #== read variables from input if needed ==#
  E_nuc::T = molecule["enuc"]

  S::Matrix{T} = read_in_oei(molecule["ovr"], basis.norb)
  H::Matrix{T} = read_in_oei(molecule["hcore"], basis.norb)

  if (scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0)
    println("Overlap matrix:")
    display(S)
    println("")

    println("Hamiltonian matrix:")
    display(H)
    println("")
  end

  #== build the orthogonalization matrix ==#
  S_evec::Matrix{T} = eigvecs(LinearAlgebra.Hermitian(S))

  S_eval_diag::Vector{T} = eigvals(LinearAlgebra.Hermitian(S))

  S_eval::Matrix{T} = zeros(basis.norb,basis.norb)
  for i::Int64 in 1:basis.norb
    S_eval[i,i] = S_eval_diag[i]
  end

  ortho::Matrix{T} = Matrix{T}(undef, basis.norb, basis.norb)
  @views ortho[:,:] = S_evec[:,:]*
    (LinearAlgebra.Diagonal(S_eval)^-0.5)[:,:]*transpose(S_evec)[:,:]

  if (scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0)
    println("Ortho matrix:")
    display(ortho)
    println("")
  end

  #== build the initial matrices ==#
  F::Matrix{T} = H
  F_eval::Vector{T} = Vector{T}(undef,basis.norb)
  F_evec::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)
  F_mo::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)

  D::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)
  C::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)

  if (MPI.Comm_rank(comm) == 0)
    println("----------------------------------------          ")
    println("       Starting RHF iterations...                 ")
    println("----------------------------------------          ")
    println(" ")
    println("Iter      Energy                   ΔE                   Drms")
  end

  E_elec::T = 0.0
  E_elec = iteration(F, D, C, H, F_eval, F_evec, F_mo, ortho, basis,
    scf_flags)
  F = deepcopy(F_mo)
  #indices_tocopy::CartesianIndices = CartesianIndices((1:size(F,1),
  #  1:size(F,2)))
  #copyto!(F, indices_tocopy, F_mo, indices_tocopy)

  E::T = E_elec + E_nuc
  E_old::T = E

  if (MPI.Comm_rank(comm) == 0)
    println(0,"     ", E)
  end

  #=============================#
  #== start scf cycles: #7-10 ==#
  #=============================#
  @time F, D, C, E, converged = scf_cycles(F, D, C, E, H, ortho, S, F_eval,
  F_evec, F_mo, E_nuc, E_elec, E_old, basis, scf_flags)

  if (!converged)
    iter_limit::Int64 = scf_flags["niter"]

    if (MPI.Comm_rank(comm) == 0)
      println(" ")
      println("----------------------------------------")
      println(" The SCF calculation did not converge.  ")
      println("      Restart data is being output.     ")
      println("----------------------------------------")
      println(" ")
    end

    calculation_fail::Dict{String,Any} = Dict(
    "success" => false,
    "error" => Dict(
      "error_type" => "convergence_error",
      "error_message" => " SCF calculation did not converge within $iter_limit
        iterations. "
      )
    )

    merge!(calculation_status, calculation_fail)

  else
    if (MPI.Comm_rank(comm) == 0)
      println(" ")
      println("----------------------------------------")
      println("   The SCF calculation has converged!   ")
      println("----------------------------------------")
      println("Total SCF Energy: ",E," h")
      println(" ")

      calculation_success::Dict{String,Any} = Dict(
      "return_result" => E,
      "success" => true,
      "properties" => Dict(
        "return_energy" => E,
        "nuclear_repulsion_energy" => E_nuc,
        #"scf_iterations" => iter,
        "scf_total_energy" => E
        )
      )

      merge!(calculation_status, calculation_success)
    end

    #if (FLAGS.SCF.debug == true)
    #  close(json_debug)
    #end
  end

  return (F, D, C, E, calculation_status)
end

function scf_cycles(F::Matrix{T}, D::Matrix{T}, C::Matrix{T}, E::T,
  H::Matrix{T}, ortho::Matrix{T}, S::Matrix{T}, F_eval::Vector{T},
  F_evec::Matrix{T}, F_mo::Matrix{T}, E_nuc::T, E_elec::T, E_old::T,
  basis::BasisStructs.Basis,
  scf_flags::Dict{String,Any}) where {T<:AbstractFloat}

  #== build DIIS arrays ==#
  ndiis::Int64 = scf_flags["ndiis"]
  F_array::Vector{Matrix{T}} = fill(Matrix{T}(undef,basis.norb,basis.norb),
    ndiis)

  e::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)
  e_array::Vector{Matrix{T}} = fill(
    Matrix{T}(undef,basis.norb,basis.norb), ndiis)
  e_array_old::Vector{Matrix{T}} = fill(
    Matrix{T}(undef,basis.norb,basis.norb), ndiis)
  F_array_old::Vector{Matrix{T}} = fill(
    Matrix{T}(undef,basis.norb,basis.norb), ndiis)

  #== build arrays needed for post-fock build iteration calculations ==#
  F_temp::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)
  D_old::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)
  ΔD::Matrix{T} = Matrix{T}(undef,basis.norb,basis.norb)

  #== build arrays needed for dynamic damping ==#
  damp_values::Vector{T} = [ 0.25, 0.75 ]
  D_damp::Vector{Matrix{T}} = [ Matrix{T}(undef,basis.norb,basis.norb)
    for i in 1:2 ]
  D_damp_rms::Vector{T} = [ zero(T), zero(T) ]

  #== build variables needed for eri batching ==#
  nsh::Int64 = length(basis.shells)
  nindices::Int64 = div(nsh*(nsh+1)*(nsh^2 + nsh + 2),8)

  quartet_batch_num_old::Int64 = fld(nindices,
    QUARTET_BATCH_SIZE) + 1

  #== build eri batch arrays ==#
  #eri_sizes::Vector{Int64} = load("tei_batch.jld",
  #  "Sizes/$quartet_batch_num_old")
  #length_eri_sizes::Int64 = length(eri_sizes)

  #@views eri_starts::Vector{Int64} = [1, [ sum(eri_sizes[1:i])+1 for i in 1:(length_eri_sizes-1)]... ]

  #eri_batch::Vector{T} = load("tei_batch.jld",
  #  "Integrals/$quartet_batch_num_old")

  eri_sizes::Vector{Int64} = []
  eri_starts::Vector{Int64} = []
  eri_batch::Vector{T} = []

  #== execute convergence procedure ==#
  scf_converged::Bool = true

  E = scf_cycles_kernel(F, D, C, E, H, ortho, S, E_nuc,
    E_elec, E_old, basis, scf_flags, ndiis, F_array, e, e_array, e_array_old,
    F_array_old, F_temp, F_eval, F_evec, F_mo, D_old, ΔD, damp_values, D_damp,
    D_damp_rms, eri_batch, eri_starts, eri_sizes, scf_converged, quartet_batch_num_old)

  #== we are done! ==#
  return (F, D, C, E, scf_converged)
end

function scf_cycles_kernel(F::Matrix{T}, D::Matrix{T}, C::Matrix{T},
  E::T, H::Matrix{T}, ortho::Matrix{T}, S::Matrix{T}, E_nuc::T, E_elec::T,
  E_old::T, basis::BasisStructs.Basis, scf_flags::Dict{String,Any},
  ndiis::Int64, F_array::Vector{Matrix{T}}, e::Matrix{T},
  e_array::Vector{Matrix{T}}, e_array_old::Vector{Matrix{T}},
  F_array_old::Vector{Matrix{T}}, F_temp::Matrix{T}, F_eval::Vector{T},
  F_evec::Matrix{T}, F_mo::Matrix{T}, D_old::Matrix{T}, ΔD::Matrix{T},
  damp_values::Vector{T}, D_damp::Vector{Matrix{T}}, D_damp_rms::Vector{T},
  eri_batch::Vector{T}, eri_starts::Vector{Int64}, eri_sizes::Vector{Int64},
  scf_converged::Bool, quartet_batch_num_old::Int64) where {T<:AbstractFloat}

  #== initialize a few more variables ==#
  comm=MPI.COMM_WORLD

  iter_limit = scf_flags["niter"]
  dele = scf_flags["dele"]
  rmsd = scf_flags["rmsd"]

  B_dim = 1
  length_eri_sizes = length(eri_sizes)

  #=================================#
  #== now we start scf iterations ==#
  #=================================#
  iter = 1
  iter_converged = false

  while !iter_converged
    #== reset eri arrays ==#
    #if quartet_batch_num_old != 1 && iter != 1
    #  resize!(eri_sizes,length_eri_sizes)
    #  resize!(eri_starts,length_eri_sizes)

    #  eri_sizes[:] = load("tei_batch.jld",
  #      "Sizes/$quartet_batch_num_old")

    #  @views eri_starts[:] = [1, [ sum(eri_sizes[1:i])+1 for i in 1:(length_eri_sizes-1)]... ]
      #eri_starts[:] = load("tei_batch.jld",
      #  "Starts/$quartet_batch_num_old")
      #@views eri_starts[:] = eri_starts[:] .- (eri_starts[1] - 1)

    #  resize!(eri_batch,sum(eri_sizes))
    #  eri_batch[:] = load("tei_batch.jld","Integrals/$quartet_batch_num_old")
    #end

    #== build fock matrix ==#
    F_temp[:,:] = twoei(F, D, eri_batch, eri_starts, eri_sizes,
      H, basis)

    F[:,:] = MPI.Allreduce(F_temp[:,:],MPI.SUM,comm)
    MPI.Barrier(comm)

    if scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0
      println("Skeleton Fock matrix:")
      display(F)
      println("")
    end

    F[:,:] .+= H[:,:]

    if scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0
      println("Total Fock matrix:")
      display(F)
      println("")
    end

    #== do DIIS ==#
    e[:,:] = F[:,:]*D[:,:]*S[:,:] .- S[:,:]*D[:,:]*F[:,:]

    e_array_old[:] = e_array[1:ndiis]
    e_array[:] = [deepcopy(e), e_array_old[1:ndiis-1]...]

    F_array_old[:] = F_array[1:ndiis]
    F_array[:] = [deepcopy(F), F_array[1:ndiis-1]...]

    if iter > 1
      B_dim += 1
      B_dim = min(B_dim,ndiis)
      try
        F[:,:] = DIIS(e_array, F_array, B_dim)
      catch
        B_dim = 2
        F[:,:] = DIIS(e_array, F_array, B_dim)
      end
    end

    #== obtain new F,D,C matrices ==#
    indices_tocopy = CartesianIndices((1:size(D,1),
      1:size(D,2)))
    copyto!(D_old, indices_tocopy, D, indices_tocopy)

    E_elec = iteration(F, D, C, H, F_eval, F_evec, F_mo,
      ortho, basis, scf_flags)

    #F = deepcopy(F_mo)
    indices_tocopy = CartesianIndices((1:size(F_mo,1),
      1:size(F_mo,2)))
    copyto!(F, indices_tocopy, F_mo, indices_tocopy)

    #== dynamic damping of density matrix ==#
    #D_damp[:] = map(x -> x*D[:,:] + (oneunit(typeof(dele))-x)*D_old[:,:],
    #  damp_values)
    #D_damp_rms = map(x->√(@∑ x-D_old x-D_old), D_damp)

    #x::T = maximum(D_damp_rms) > oneunit(typeof(dele)) ? minimum(damp_values) :
    #  maximum(damp_values)
    #D[:,:] = x*D[:,:] + (oneunit(typeof(dele))-x)*D_old[:,:]

    #== check for convergence ==#
    @views ΔD[:,:] = D[:,:] .- D_old[:,:]
    D_rms = √(@∑ ΔD ΔD)

    E = E_elec+E_nuc
    ΔE = E - E_old

    if MPI.Comm_rank(comm) == 0
      println(iter,"     ", E,"     ", ΔE,"     ", D_rms)
    end

    iter_converged = (abs(ΔE) <= dele) && (D_rms <= rmsd)
    iter += 1
    if iter > iter_limit
      scf_converged = false
      break
    end

    #== if not converged, replace old D and E values for next iteration ==#
    #D_old = deepcopy(D)
    E_old = E
  end

  return E
end
#=
"""
	 twoei(F::Array{T}, D::Array{T}, tei::Array{T}, H::Array{T})
Summary
======
Perform Fock build step.

Arguments
======
F = Current iteration's Fock Matrix

D = Current iteration's Density Matrix

tei = Two-electron integral array

H = One-electron Hamiltonian Matrix
"""
=#

function twoei(F::Matrix{T}, D::Matrix{T},
  eri_batch::Vector{T}, eri_starts::Vector{Int64}, eri_sizes::Vector{Int64},
  H::Matrix{T}, basis::BasisStructs.Basis) where {T<:AbstractFloat}

  fill!(F,zero(T))

  nsh = length(basis.shells)
  nindices = (nsh*(nsh+1)*(nsh^2 + nsh + 2)) >> 3 #bitwise divide by 8

  quartet_batch_num_old = fld(nindices,
    QUARTET_BATCH_SIZE) + 1

  mutex = Base.Threads.Mutex()
  thread_index_counter = Threads.Atomic{Int64}(nindices)

  Threads.@threads for thread in 1:Threads.nthreads()
    F_priv = zeros(basis.norb,basis.norb)

    max_shell_am = MAX_SHELL_AM
    eri_quartet_batch = Vector{T}(undef,1296)

    bra = ShPair(basis.shells[1], basis.shells[1])
    ket = ShPair(basis.shells[1], basis.shells[1])
    quartet = ShQuartet(bra,ket)

    twoei_thread_kernel(F, D, eri_batch, eri_starts, eri_sizes,
      H, basis, mutex, thread_index_counter, F_priv, eri_quartet_batch,
      bra, ket, quartet, nindices, quartet_batch_num_old)

    lock(mutex)
    F[:,:] .+= F_priv[:,:]
    unlock(mutex)
  end

  for iorb in 1:basis.norb, jorb in 1:basis.norb
    if iorb != jorb F[iorb,jorb] /= 2.0 end
  end

  return F
end

@inline function twoei_thread_kernel(F::Matrix{T}, D::Matrix{T},
  eri_batch::Vector{T}, eri_starts::Vector{Int64}, eri_sizes::Vector{Int64},
  H::Matrix{T}, basis::BasisStructs.Basis, mutex::Base.Threads.Mutex,
  thread_index_counter::Threads.Atomic{Int64}, F_priv::Matrix{T},
  eri_quartet_batch::Vector{T}, bra::ShPair , ket::ShPair, quartet::ShQuartet,
  nindices::Int64, quartet_batch_num_old::Int64) where {T<:AbstractFloat}

  comm=MPI.COMM_WORLD
  eri_batch_length = length(eri_batch)

  while true
    ijkl_index = Threads.atomic_sub!(thread_index_counter, 1)
    if ijkl_index < 1 break end

    if MPI.Comm_rank(comm) != ijkl_index%MPI.Comm_size(comm) continue end
    bra_pair = get_new_index(ijkl_index)
    ket_pair_sub = (bra_pair*(bra_pair-1)) >> 1
    ket_pair = ijkl_index-ket_pair_sub

    ish = get_new_index(bra_pair)
    jsh_sub = (ish*(ish-1)) >> 1
    jsh = bra_pair-jsh_sub

    ksh = get_new_index(ket_pair)
    lsh_sub = (ksh*(ksh-1)) >> 1
    lsh = ket_pair-lsh_sub

    ijsh = index(ish,jsh)
    klsh = index(ksh,lsh)

    if klsh > ijsh ish,jsh,ksh,lsh = ksh,lsh,ish,jsh end

    bra.sh_a = basis[ish]
    bra.sh_b = basis[jsh]

    ket.sh_a = basis[ksh]
    ket.sh_b = basis[lsh]

    quartet.bra = bra
    quartet.ket = ket

    qnum_ij = (ish*(ish-1)) >> 1
    qnum_ij += jsh

    qnum_kl = (ksh*(ksh-1)) >> 1
    qnum_kl += lsh

    quartet_num = (qnum_ij*(qnum_ij-1)) >> 1
    quartet_num += qnum_kl - 1

    #println("QUARTET: $ish, $jsh, $ksh, $lsh ($quartet_num):")

   # quartet_batch_num::Int64 = fld(quartet_num,
   #   QUARTET_BATCH_SIZE) + 1

    #if quartet_batch_num != quartet_batch_num_old
    #  if length(eri_starts) != QUARTET_BATCH_SIZE && length(eri_sizes) != QUARTET_BATCH_SIZE
    #    resize!(eri_sizes,QUARTET_BATCH_SIZE)
    #    resize!(eri_starts,QUARTET_BATCH_SIZE)
    #  end

    #  eri_sizes[:] = load("tei_batch.jld",
    #    "Sizes/$quartet_batch_num")

      #@views eri_starts[:] = [1, [ sum(eri_sizes[1:i])+1 for i in 1:(QUARTET_BATCH_SIZE-1)]... ]
      #eri_starts[:] = load("tei_batch.jld","Starts/$quartet_batch_num")
      #@views eri_starts[:] = eri_starts[:] .- (eri_starts[1] - 1)

    #  resize!(eri_batch,sum(eri_sizes))
    #  eri_batch[:] = load("tei_batch.jld","Integrals/$quartet_batch_num")

    #  quartet_batch_num_old = quartet_batch_num
    #end

    #quartet_num_in_batch::Int64 = quartet_num - QUARTET_BATCH_SIZE*
    #  (quartet_batch_num-1) + 1

    #starting::Int64 = eri_starts[quartet_num_in_batch]
    #ending::Int64 = starting + eri_sizes[quartet_num_in_batch] - 1
    #batch_ending_final::Int64 = ending - starting + 1

    #@views eri_quartet_batch[1:batch_ending_final] = eri_batch[starting:ending]
    #eri_quartet_batch = @view eri_batch[starting:ending]

    shellquart_direct(ish,jsh,ksh,lsh,eri_quartet_batch)

    #if abs(maximum(eri_quartet_batch)) > 1E-10
      dirfck(F_priv, D, eri_quartet_batch, quartet,
        ish, jsh, ksh, lsh)
    #end
  end
end

@inline function shellquart_direct(ish::Int64, jsh::Int64, ksh::Int64, lsh::Int64,
  eri_quartet_batch::Vector{T}) where {T<:AbstractFloat}

  SIMINT.retrieve_eris(ish, jsh, ksh, lsh, eri_quartet_batch)
end


@noinline function dirfck(F_priv::Matrix{T}, D::Matrix{T}, eri_batch::Vector{T},
  quartet::ShQuartet, ish::Int64, jsh::Int64,
  ksh::Int64, lsh::Int64) where {T<:AbstractFloat}

  norb = size(D)[1]

  spμ = quartet.bra.sh_a.sp
  spν = quartet.bra.sh_b.sp
  spλ = quartet.ket.sh_a.sp
  spσ = quartet.ket.sh_b.sp

  μνλσ = 0

  for spi in 0:spμ, spj in 0:spν
    nμ = 0
    pμ = quartet.bra.sh_a.pos
    if spμ == 1
      nμ = spi == 1 ? 3 : 1
      pμ += spi == 1 ? 1 : 0
    else
      nμ = quartet.bra.sh_a.nbas
    end

    nν = 0
    pν = quartet.bra.sh_b.pos
    if spν == 1
      nν = spj == 1 ? 3 : 1
      pν += spj == 1 ? 1 : 0
    else
      nν = quartet.bra.sh_b.nbas
    end

    for spk in 0:spλ, spl in 0:spσ
      nλ = 0
      pλ = quartet.ket.sh_a.pos
      if spλ == 1
        nλ = spk == 1 ? 3 : 1
        pλ += spk == 1 ? 1 : 0
      else
        nλ = quartet.ket.sh_a.nbas
      end

      nσ = 0
      pσ = quartet.ket.sh_b.pos
      if spσ == 1
        nσ = spl == 1 ? 3 : 1
        pσ += spl == 1 ? 1 : 0
      else
        nσ = quartet.ket.sh_b.nbas
      end

      for μμ in pμ:pμ+(nμ-1), νν in pν:pν+(nν-1)
        μ, ν = μμ,νν
        #if (μμ < νν) μ, ν = ν, μ end

        μν = index(μμ,νν)

        for λλ in pλ:pλ+(nλ-1), σσ in pσ:pσ+(nσ-1)
          λ, σ = λλ,σσ
          #if (λλ < σσ) λ, σ = σ, λ end

          λσ = index(λλ,σσ)

          #if (μν < λσ) μ, ν, λ, σ = λ, σ, μ, ν end
          #if (μν < λσ)
          #  μνλσ += 1
          #  continue
          #end
          #print("$μμ, $νν, $λλ, $σσ => ")
          if (μμ < νν)
            μνλσ += 1
            #println("DO CONTINUE")
            continue
          end

          if (λλ < σσ)
            μνλσ += 1
            #println("DO CONTINUE")
            continue
          end

          if (μν < λσ)
            do_continue = false

            do_continue, μ, ν, λ, σ = sort_braket(μμ, νν, λλ, σσ, ish, jsh,
              ksh, lsh, nμ, nν, nλ, nσ)

            if do_continue
              μνλσ += 1
              #println("DO CONTINUE")
              continue
            end
          end

          μνλσ += 1

	        eri = eri_batch[μνλσ]
          #eri::T = 0
          if (abs(eri) <= 1E-10) continue end

          #println("$μ, $ν, $λ, $σ, $eri")
	        eri *= (μ == ν) ? 0.5 : 1.0
	        eri *= (λ == σ) ? 0.5 : 1.0
	        eri *= ((μ == λ) && (ν == σ)) ? 0.5 : 1.0

	        F_priv[λ,σ] += 4.0 * D[μ,ν] * eri
	        F_priv[μ,ν] += 4.0 * D[λ,σ] * eri
          F_priv[μ,λ] -= D[ν,σ] * eri
	        F_priv[μ,σ] -= D[ν,λ] * eri
          F_priv[ν,λ] -= D[max(μ,σ),min(μ,σ)] * eri
          F_priv[ν,σ] -= D[max(μ,λ),min(μ,λ)] * eri

          if λ != σ F_priv[σ,λ] += 4.0 * D[μ,ν] * eri end
	        if μ != ν F_priv[ν,μ] += 4.0 * D[λ,σ] * eri end
          if μ != λ F_priv[λ,μ] -= D[ν,σ] * eri end
	        if μ != σ F_priv[σ,μ] -= D[ν,λ] * eri end
          if ν != λ F_priv[λ,ν] -= D[max(μ,σ),min(μ,σ)] * eri end
	        if ν != σ F_priv[σ,ν] -= D[max(μ,λ),min(μ,λ)] * eri end
        end
      end
    end
  end
end

#=
"""
	 iteration(F::Matrix{T}, D::Matrix{T}, H::Matrix{T}, ortho::Matrix{T})
Summary
======
Perform single SCF iteration.

Arguments
======
F = Current iteration's Fock Matrix

D = Current iteration's Density Matrix

H = One-electron Hamiltonian Matrix

ortho = Symmetric Orthogonalization Matrix
"""
=#
function iteration(F_μν::Matrix{T}, D::Matrix{T}, C::Matrix{T},
  H::Matrix{T}, F_eval::Vector{T}, F_evec::Matrix{T}, F_mo::Matrix{T},
  ortho::Matrix{T}, basis::BasisStructs.Basis,
  scf_flags::Dict{String,Any}) where {T<:AbstractFloat}

  comm=MPI.COMM_WORLD

  #== obtain new orbital coefficients ==#
  @views F_mo[:,:] = transpose(ortho)[:,:]*F_μν[:,:]*ortho[:,:]

  F_eval[:] = eigvals(LinearAlgebra.Hermitian(F_mo))

  @views F_evec[:,:] = eigvecs(LinearAlgebra.Hermitian(F_mo))[:,:]
  @views F_evec[:,:] = F_evec[:,sortperm(F_eval)] #sort evecs according to sorted evals

  #copyto!(F_evec, CartesianIndices((1:size(F_evec,1), 1:size(F_evec,2))),
  #  F_evec[:,sortperm(F_eval)], CartesianIndices((1:size(F_evec,1), 1:size(F_evec,2))))

  @views C[:,:] = ortho[:,:]*F_evec[:,:]

  if (scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0)
    println("New orbitals:")
    display(C)
    println("")
  end

  #== build new density matrix ==#
  nocc = div(basis.nels,2)
  norb = basis.norb

  for i in 1:basis.norb, j in 1:basis.norb
    @views D[i,j] = @∑ C[i,1:nocc] C[j,1:nocc]
    #D[i,j] = @∑ C[1:nocc,i] C[1:nocc,j]
    D[i,j] *= 2
  end

  if (scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0)
    println("New density matrix:")
    display(D)
    println("")
  end

  #== compute new SCF energy ==#
  EHF1 = @∑ D F_μν
  EHF2 = @∑ D H
  E_elec = (EHF1 + EHF2)/2

  if (scf_flags["debug"] == true && MPI.Comm_rank(comm) == 0)
    println("New energy:")
    println("$EHF1, $EHF2")
    println("")
  end

  return E_elec
end
