### This file contains public API ###

"""
    Mesh

A struct representing a 3D mesh. Every three vertices represents a triangle. Properties per
    triangle are stored in a dictionary of arrays.

# Fields
- `vertices`: A vector containing the vertices of the mesh.
- `properties`: A dictionary containing additional properties of the mesh (arrays of properties per triangle).

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> p = Dict{Symbol, AbstractVector}(:normal => [Vec(0.0, 0.0, 1.0)]);

julia> m = Mesh(v, p);
```
"""
struct Mesh{FT}
    vertices::Vector{Vec{FT}}
    properties::Dict{Symbol, AbstractVector}
end

"""
    Mesh(type = Float64)

Generate an empty triangular dense mesh that represents a primitive or 3D scene.
By default a `Mesh` object will only accept coordinates in double floating
precision (`Float64`) but a lower precision can be generated by specifying the
corresponding data type as in `Mesh(Float32)`.

# Arguments
- `type`: The floating-point precision type for the mesh data (default is `Float64`).

# Returns
A `Mesh` object with no vertices or normals.

# Example
```jldoctest
julia> m = Mesh();

julia> nvertices(m);

julia> ntriangles(m);

julia> Mesh(Float32);
```
"""
function Mesh(::Type{FT} = Float64) where {FT<:AbstractFloat}
    Mesh(Vec{FT}[], Dict{Symbol, AbstractVector}())
end

"""
    Mesh(nt, type)

Generate a triangular dense mesh with enough memory allocated to store `nt`
triangles. The behaviour is equivalent to generating an empty
mesh but may be computationally more efficient when appending a large number of
primitives. If a lower floating precision is required, this may be specified
as an optional third argument as in `Mesh(10, Float32)`.

# Arguments
- `nt`: The number of triangles to allocate memory for.
- `type`: The floating-point precision type for the mesh data (default is `Float64`).

# Returns
A `Mesh` object with no vertices or normals.

# Example
```jldoctest
julia> m = Mesh(1_000);

julia> nvertices(m);

julia> ntriangles(m);

julia> Mesh(1_000, Float32);
```
"""
function Mesh(nt::Number, ::Type{FT} = Float64) where {FT<:AbstractFloat}
    nv = 3nt
    v = Vec{FT}[]
    sizehint!(v, nv)
    n = Vec{FT}[]
    sizehint!(n, nt)
    Mesh(v, Dict{Symbol, AbstractVector}(:normal => n))
end



"""
    Mesh(vertices)

Generate a triangular mesh from a vector of vertices.

# Arguments
- `vertices`: List of vertices (each vertex implement as `Vec`).

# Returns
A `Mesh` object.

# Example
```jldoctest
julia> verts = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> Mesh(verts);
```
"""
function Mesh(vertices::Vector{<:Vec})
    VT = eltype(vertices)
    m = Mesh(vertices, Dict{Symbol, AbstractVector}())
    update_normals!(m)
    return m
end


# Auxilliary function to add properties (from p2 to p1)
function add_properties!(p1::Dict{Symbol, AbstractVector}, p2::Dict{Symbol, AbstractVector})
    # Both are empty
    isempty(p1) && isempty(p2) && (return nothing)
    # If not, they must have the same properties
    k1, k2 = (keys(p1), keys(p2))
    @assert k1 == k2 "Properties of both meshes must be the same"
    # Add properties (we assume each property is stored in an array-like structure)
    for k in k1
        @inbounds append!(p1[k], p2[k])
    end
    return p1
end

"""
    add_property!(m::Mesh, prop::Symbol, data, nt = ntriangles(m))

Add a property to a mesh. The property is identified by a name (`prop`) and is stored as an
array of values (`data`), one per triangle. If the property already exists, the new data is
appended to the existing property, otherwise a new property is created. It is possible to
pass a single object for `data`, in which case the property will be set to the same value for
all triangles.

# Arguments
- `mesh`: The mesh to which the property is to be added.
- `prop`: The name of the property to be added as a `Symbol`.
- `data`: The data to be added to the property (an array or a single value).
- `nt`: The number of triangles to be assumed if `data` is not an array. By default this is the number of triangles in the mesh.

# Returns
The mesh with updated properties.

# Example
```jldoctest
julia> r = Rectangle();

julia> add_property!(r, :absorbed_PAR, [0.0, 0.0]);
```
"""
function add_property!(m::Mesh, prop::Symbol, data, nt = ntriangles(m))
    # Check if the data is an array and if not convert it to an array with length nt
    vecdata = data isa AbstractVector ? data : fill(data, nt)
    if !haskey(properties(m), prop)
        properties(m)[prop] = vecdata
    else
        append!(properties(m)[prop], vecdata)
    end
    return m
end

"""
    Mesh(meshes)

Merge multiple meshes into a single one

# Arguments
- `meshes`: Vector of meshes to merge.

# Returns
A new `Mesh` object that is the result of merging all the input meshes.

# Example
```jldoctest
julia> e = Ellipse(length = 2.0, width = 2.0, n = 10);

julia> r = Rectangle(length = 10.0, width = 0.2);

julia> m = Mesh([e,r]);
```
"""
function Mesh(meshes::Vector{<:Mesh})
    @assert !isempty(meshes) "At least one mesh must be provided"
    @inbounds verts = copy(vertices(meshes[1]))
    @inbounds props = properties(meshes[1])
    if length(meshes) > 1
        @inbounds for i in 2:length(meshes)
            append!(verts, vertices(meshes[i]))
            add_properties!(props, properties(meshes[i]))
        end
    end
    Mesh(verts, props)
end

# Calculate the normals of a mesh and add them (deals with partially compute normals)
function update_normals!(m::Mesh{FT}) where {FT<:AbstractFloat}
    # 1. Check if there is a property called :normal and if not create it
    if !haskey(properties(m), :normal)
        properties(m)[:normal] = Vec{FT}[]
    end
    vs = vertices(m)
    lv = length(vs)
    # 2. If the property :normal is empty, compute the normals for all vertices
    if isempty(normals(m))
        for i in 1:3:lv
            @inbounds v1, v2, v3 = vs[i], vs[i+1], vs[i+2]
            n = L.normalize(L.cross(v2 .- v1, v3 .- v1))
            push!(normals(m), n)
        end
    else
    # 3. If the property :normal is not empty, compute the normals for the remaining vertices
        ln = length(normals(m))
        for i in 3ln:3:(lv - 3)
            @inbounds v1, v2, v3 = vs[i + 1], vs[i + 2], vs[i + 3]
            n = L.normalize(L.cross(v2 .- v1, v3 .- v1))
            push!(normals(m), n)
        end
    end
    return nothing
end

"""
    eltype(mesh::Mesh)

Extract the the type used to represent coordinates in a mesh (e.g., `Float64`).

# Fields
- `mesh`: The mesh from which to extract the element type.

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> m = Mesh(v);

julia> eltype(m);
```
"""
Base.eltype(m::Mesh{VT}) where VT = eltype(VT)
Base.eltype(::Type{Mesh{VT}}) where VT = eltype(VT)


# Accessor functions
"""
    ntriangles(mesh)

Extract the number of triangles in a mesh.

# Arguments
- `mesh`: The mesh from which to extract the number of triangles.

# Returns
The number of triangles in the mesh as an integer.

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> m = Mesh(v);

julia> ntriangles(m);
```
"""
ntriangles(mesh::Mesh) = div(length(vertices(mesh)), 3)

"""
    nvertices(mesh)

The number of vertices in a mesh.

# Arguments
- `mesh`: The mesh from which to retrieve the number of vertices.

# Returns
The number of vertices in the mesh as an integer.

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> m = Mesh(v);

julia> nvertices(m);
```
"""
nvertices(mesh::Mesh) = length(vertices(mesh))

# Accessor functions
"""
    vertices(mesh::Mesh)

Retrieve the vertices of a mesh.

# Arguments
- `mesh`: The mesh from which to retrieve the vertices.

# Returns
A vector containing the vertices of the mesh.

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> m = Mesh(v);

julia> vertices(m);
```
"""
vertices(mesh::Mesh) = mesh.vertices

"""
    normals(mesh::Mesh)

Retrieve the normals of a mesh.

# Arguments
- `mesh`: The mesh from which to retrieve the normals.

# Returns
A vector containing the normals of the mesh.

# Example
```jldoctest; output=false
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0)];

julia> m = Mesh(v);

julia> normals(m);
```
"""
normals(mesh::Mesh) = properties(mesh)[:normal]

"""
    properties(mesh::Mesh)

Retrieve the properties of a mesh. Properties are stored as a dictionary with one entry per
type of property. Each property is an array of objects, one per triangle. Each property is
identified by a symbol (e.g.).

# Arguments
- `mesh`: The mesh from which to retrieve the normals.

# Returns
A vector containing the normals of the mesh.

# Example
```jldoctest; output=false
julia> r = Rectangle();

julia> add_property!(r, :absorbed_PAR, [0.0, 0.0]);

julia> properties(r);
```
"""
properties(mesh::Mesh) = mesh.properties

"""
    get_triangle(m::Mesh, i)

Retrieve the vertices for the i-th triangle in a mesh.

# Arguments
- `mesh`: The mesh from which to retrieve the triangle.
- `i`: The index of the triangle to retrieve.

# Returns
A vector containing the three vertices defining the i-th triangle.

# Example
```jldoctest
julia> v = [Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(1.0, 0.0, 0.0),
            Vec(0.0, 0.0, 0.0), Vec(0.0, 1.0, 0.0), Vec(0.0, 0.0, 1.0)];

julia> m = Mesh(v);

julia> get_triangle(m, 2);
```
"""
function get_triangle(m::Mesh, i)
    v = vertices(m)
    get_triangle(v, i)
end

# Internal function to retrieve the vertices of the i-th triangle (give list of vertices)
function get_triangle(v::AbstractVector, i)
    i1 = (i - 1)*3 + 1
    @view v[SVector{3,Int}(i1, i1+1, i1+2)]
end

# Area of a triangle given its vertices
function area_triangle(v1::Vec{FT}, v2::Vec{FT}, v3::Vec{FT})::FT where {FT<:AbstractFloat}
    e1 = v2 .- v1
    e2 = v3 .- v1
    FT(0.5) * L.norm(L.cross(e1, e2))
end

"""
    area(mesh::Mesh)

Total surface area of a mesh (as the sum of areas of individual triangles).

# Arguments
- `mesh`: Mesh which area is to be calculated.

# Returns
The total surface area of the mesh as a number.

# Example
```jldoctest
julia> r = Rectangle(length = 10.0, width = 0.2);

julia> area(r);

julia> r = Rectangle(length = 10f0, width = 0.2f0);

julia> area(r);
```
"""
function area(m::Mesh)
    sum(area_triangle(get_triangle(m, i)...) for i in 1:ntriangles(m))
end

"""
    areas(m::Mesh)

A vector with the areas of the different triangles that form a mesh.

# Arguments
- `mesh`: Mesh which areas are to be calculated.

# Returns
A vector with the areas of the different triangles that form the mesh.

# Example
```jldoctest
julia> r = Rectangle(length = 10.0, width = 0.2);

julia> areas(r);

julia> r = Rectangle(length = 10f0, width = 0.2f0);

julia> areas(r);
```
"""
areas(m::Mesh) = [area_triangle(get_triangle(m, i)...) for i in 1:ntriangles(m)]

# Check if two meshes are equal (mostly for testing)
function Base.:(==)(m1::Mesh, m2::Mesh)
    vertices(m1) == vertices(m2) && normals(m1) == normals(m2)
end

# Check if two meshes are approximately equal (mostly for testing)
function Base.isapprox(m1::Mesh, m2::Mesh; atol::Real = 0.0,
                      rtol::Real = atol > 0.0 ? 0.0 : sqrt(eps(1.0)))
    isapprox(vertices(m1), vertices(m2), atol = atol, rtol = rtol) &&
        isapprox(normals(m1), normals(m2), atol = atol, rtol = rtol)
end


"""
    add!(mesh1, mesh2; kwargs...)

Manually add a mesh to an existing mesh with optional properties captured as keywords. Make
sure to be consistent with the properties (both meshes should end up with the same lsit of
properties). For example, if the scene was created with `:colors``, then you should provide
`:colors`` for the new mesh as well.

# Arguments
- `mesh1`: The current mesh we want to extend.
- `mesh1`: A new mesh we want to add.
- `kwargs`: Properties to be set per triangle in the new mesh.

# Example
```jldoctest
julia> t1 = Triangle(length = 1.0, width = 1.0);

julia> using ColorTypes: RGB

julia> add_property!(t1, :colors, rand(RGB));

julia> t2 = Rectangle(length = 5.0, width = 0.5);

julia> add!(t1, t2, colors = rand(RGB));
```
"""
function add!(mesh1, mesh2; kwargs...)
    # Make sure the mesh contains normals
    update_normals!(mesh2)
    # Add the vertices and normals
    append!(vertices(mesh1), vertices(mesh2))
    add_property!(mesh1, :normal, normals(mesh2))
    # Set optional properties per triangle
    for (k, v) in kwargs
        add_property!(mesh1, k, v, ntriangles(mesh2))
    end
    return mesh1
end
