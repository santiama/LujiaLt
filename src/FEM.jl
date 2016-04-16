
"""
# `module FEM`

Module that collects some basic finite element functionality for
application with the Cauchy--Born model. The core is a Julia
wrapper for Qhull which goes via `PyCall` and `scipy.spatial.Delaunay`.

## Quick example

```
using LujiaLt.FEM
tri = Triangulation(rand(2, 10))
plot(tri; xradius=0.02)
```

## List of types and methods

Look at the respective docs for more info.

* `Triangulation` : Delauany triangulation from arbitrary set of points
* `nT, nX` : number of elements / number of nodes
* `elements` : iterator over elements
* `P1_element` : some useful generic computations associated with P1-FEM
* `plot` : display the mesh
* `locate` : find elements to which some points belong

## Dependencies:

* `Compose` for plotting 
* `PyCall` for calling Python / scipy
* working Python installation with `scipy`

## TODO

* Constrained Delaunay triangulation
* maybe admitting different triangulation packages
"""
module FEM

using PyCall
using Compose

@pyimport scipy.spatial as scipy_spatial

export Triangulation
export nT, nX
export elements
export locate
export P1_element
export plot

"""`type Triangulation`

An elementary triangulation wrapper type, to allow in principle usage of
different background triangulation packages. The current implementation uses
`scipy.spatial.Delaunay`, which is a [Qhull](http://www.qhull.org) wrapper.

* `X` : dim x Npoints array containing the vertices
* `T` : dim+1 x Ntriangles array containing the element information

## Constructor

* To construct a Delaunay triangulation create a 2 x Npoints or a Npoints x 2
array `X`, where Npoints must be larger than 2, and simply call
`tri = Triangulation(X)`.

## Usage via iterator

```
# assume X are the FE nodes an U the nodal values
tri = Triangulation(X)
for iT in elements(tri)
    vol, F, Du = P1_element(iT, tri, U)
    # do something with it 
end
```
"""
type Triangulation
    X::Matrix{Float64}
    T::Matrix{Int}
    pyo::PyObject
end


function Triangulation(X)
    # reshape X
    if size(X, 1) == 2
        X = X'
    elseif size(X, 2) != 2
        error("Triangulation : size(X) must be (2, N) or (N, 2)")
    end
    # call the Qhull code via PyCall via scipy bindings
    tri = scipy_spatial.Delaunay(X)
    # return the Julia object
    return Triangulation(X', tri[:simplices]' + 1, tri)
end

"return number of elements in the triangulation"
nT(tri::Triangulation) = size(tri.T, 2)

"returns number of nodes in the triangulation"
nX(tri::Triangulation) = size(tri.X, 2)

"auxiliary data-type to iterate over finite elements"
type ElementIterator
    tri::Triangulation
    i::Int
end

"creates an iterator over elements"
elements(tri::Triangulation) = ElementIterator(tri, 0)
done(tri::Triangulation, state::ElementIterator) = (state.i == nT(tri))
next(tri::Triangulation, state::ElementIterator) =
    (state.i+1, ElementIterator(tri, state.i+1))

"compute the P1 gradient in the reference triangle"
ref_grad(t::Vector{Int}, V::Matrix{Float64}) = V[:, t[2:3]] .- V[:, t[1]]


"""compute some information related to P1-FEM:

* `P1_element(el::Int, tri::Triangulation) -> vol, F`, where `vol` is the 
    element volume and `F` the deformation matrix.
* `P1_element(el::Int, tri::Triangulation, U) -> vol, F, Du`, 
    where `Du` of dimension r x dim (dim=2) is the gradient of the P1 function
        represented by `U` which is given as a `r x nX` array with `r` being the 
        range dimension.
"""
function P1_element(el::Int, tri::Triangulation)
    F = ref_grad(tri.T[:, el], tri.X)
    return det(F) / 2, F
end

function P1_element(el::Int, tri::Triangulation, U::Matrix{Float64})
    vol, F = P1_element(el, tri)
    DU_ref = ref_grad(tri.T[:, el], U)
    invF = [F[2,2] -F[1,2]; -F[2,1] F[1,1]] * 2 / vol
    return vol, F, DU_ref * invF
end


"""
find element indices to which the provided points belong.

## Parameters
* `P` : 2 x M, list of points that we want to locate
* `tri` : Triangulation
"""
locate(P::Matrix{Float64}, tri::Triangulation) = tri.pyo[:find_simplex](P') + 1


# ########################## PLOTTING ############################


function plot(tri; width=15cm, height=:auto, xradius=0.25, atcol="tomato", 
              buffer=2*xradius, elcol = "aliceblue", linecol="darkblue",
              lwidth=1.0)
    
    # create a canvas
    xLim = [extrema(tri.X[1,:])...]
    dat_width = xLim[2]-xLim[1]
    yLim = [extrema(tri.X[2,:])...]
    dat_height = yLim[2]-yLim[1]
    xLim[1] -= buffer; xLim[2] += buffer; dat_width = xLim[2]-xLim[1]
    yLim[1] -= buffer; yLim[2] += buffer; dat_height = yLim[2]-yLim[1]

    if height == :auto
        height = width * (dat_height / dat_width)
    end
    ub = UnitBox(xLim[1], yLim[1], dat_width, dat_height)
    
    # draw the elements
    points = Tuple{Float64, Float64}[]
    for n = 1:nT(tri)
        p = [tri.X[:, tri.T[:, n]] tri.X[:, tri.T[1,n]]]
        for m = 1:size(p, 2)
            push!(points, tuple(p[1, m], p[2,m]))
        end
        push!(points, tuple(NaN, NaN))
    end
    c_ctx = compose(context(units=ub), polygon(points), 
                    fill(elcol), stroke(linecol), linewidth(lwidth) )
    
    # draw the nodes
    a_ctx = context(units=ub)
    if xradius > 0
        a_ctx = compose(a_ctx,
                        circle(tri.X[1,:], tri.X[2,:], [xradius]), 
                        fill(atcol), stroke(linecol) )
    end
   
    return compose(context(), a_ctx, c_ctx)
end


end



# """compute unique set of edges: for now this is an auxiliary function use
# for plotting, but it could become something more useful for 
# """
# function _edges_(tri::Triangulation)
#     T = tri.T
#     S = [ T[1,:] T[1,:] T[2,:] T[2,:] T[3,:] T[3,:];
#           T[2,:] T[3,:] T[1,:] T[3,:] T[1,:] T[2,:] ]
#     S = sort(S, 1)
#     return unique(S, 2)
# end
