import PlantGeomPrimitives as G
using Test
import CoordinateTransformations: SDiagonal, LinearMap

let

    # Standard solid frustum primitive
    c = G.SolidFrustum(length = 2.0, width = 1.0, height = 1.0, ratio = 0.5, n = 40)
    @test c isa G.Mesh
    exact_area = (pi + 0.5pi) / 2 * sqrt(2^2 + 0.25^2) + pi * (0.5^2 + 0.25^2)
    @test abs(G.area(c) - exact_area) < 0.15
    @test G.nvertices(c) == 120
    @test G.ntriangles(c) == div(G.nvertices(c), 3)
    @test length(G.normals(c)) == G.ntriangles(c)

    # Check that it works at lower precision
    c = G.SolidFrustum(length = 2.0f0, width = 1.0f0, height = 1.0f0, ratio = 0.5f0, n = 40)
    @test c isa G.Mesh
    exact_area = (pi + 0.5pi) / 2 * sqrt(2^2 + 0.25^2) + pi * (0.5^2 + 0.25^2)
    @test abs(G.area(c) - exact_area) < 0.15f0
    @test G.nvertices(c) == 120
    @test G.ntriangles(c) == div(G.nvertices(c), 3)
    @test length(G.normals(c)) == G.ntriangles(c)

    # Merging two meshes
    c = G.SolidFrustum(length = 2.0, width = 1.0, height = 1.0, ratio = 0.5, n = 40)
    c2 = G.SolidFrustum(length = 3.0, width = 0.1, height = 0.2, ratio = 1 / 10, n = 40)
    function foo()
        c = G.SolidFrustum(length = 2.0, width = 1.0, height = 1.0, ratio = 0.5, n = 40)
        c2 = G.SolidFrustum(length = 3.0, width = 0.1, height = 0.2, ratio = 1 / 10, n = 40)
        m = G.Mesh([c, c2])
    end
    m = foo()
    @test G.nvertices(m) == G.nvertices(c) + G.nvertices(c2)
    @test G.ntriangles(m) == G.ntriangles(c) + G.ntriangles(c2)
    @test abs(G.area(m) - (G.area(c) + G.area(c2))) < 1e-15

    # Create a frustum using affine maps
    scale = LinearMap(SDiagonal(0.2 / 2, 0.1 / 2, 3.0))
    c3 = G.SolidFrustum(1 / 10.0, scale, n = 40)
    @test G.normals(c3) == G.normals(c2)
    @test G.vertices(c3) == G.vertices(c2)

    # Create a frustum ussing affine maps and add it to an existing mesh
    function foo2()
        scale = LinearMap(SDiagonal(0.2 / 2, 0.1 / 2, 3.0))
        m = G.SolidFrustum(length = 2.0, width = 1.0, height = 1.0, ratio = 0.5, n = 40)
        G.SolidFrustum!(m, 1 / 10, scale, n = 40)
        m
    end
    m2 = foo2()
    @test G.normals(m2) == G.normals(m)
    @test G.vertices(m2) == G.vertices(m)
    @test m2.vertices == m.vertices
end

# import GLMakie
# import PlantViz as PV
# PV.render(m, normals = true)
# PV.render!(m2, normals = true, color = :red)
