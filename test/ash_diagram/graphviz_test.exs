defmodule AshDiagram.GraphvizTest do
  use ExUnit.Case, async: true

  alias AshDiagram.C4
  alias AshDiagram.Class
  alias AshDiagram.Class.Relationship.Pointer
  alias AshDiagram.Data
  alias AshDiagram.EntityRelationship
  alias AshDiagram.Flow.Domain
  alias AshDiagram.Graphviz

  doctest Graphviz

  @spec dot(diagram :: AshDiagram.t(), options :: Graphviz.options()) :: String.t()
  defp dot(diagram, options \\ []), do: diagram |> Graphviz.compose(options) |> IO.iodata_to_binary()

  describe "class diagrams" do
    setup do
      diagram = %Class{
        entries: [
          %Class.Class{
            id: "MyApp.User",
            label: "User",
            members: [
              %Class.Field{visibility: :public, name: "email", type: "String"},
              %Class.Method{
                visibility: :public,
                name: "register",
                arguments: [{"params", {:generic, "Map", "String"}}],
                type: "create"
              }
            ]
          },
          %Class.Class{id: "MyApp.Post", label: "Post"},
          %Class.Relationship{
            left: %Pointer{class: "MyApp.User", cardinality: "1", type: :aggregation},
            right: %Pointer{class: "MyApp.Post", cardinality: "*"},
            style: :dashed
          }
        ]
      }

      {:ok, diagram: diagram}
    end

    test "draws each class as a table of its fields, then its methods", %{diagram: diagram} do
      dot = dot(diagram)

      assert dot =~ ~s("MyApp.User" [label=<<TABLE)
      assert dot =~ "<B>User</B>"

      assert dot =~
               ~s{<TR><TD ALIGN="LEFT"><FONT FACE="Courier">+String email</FONT></TD></TR><HR/><TR><TD ALIGN="LEFT"><FONT FACE="Courier">+register(Map&lt;String&gt; params) : create</FONT></TD></TR>}
    end

    test "draws relationships with their ends, cardinalities and style", %{diagram: diagram} do
      assert dot(diagram) =~
               ~s("MyApp.User" -> "MyApp.Post" [dir=both, arrowtail=odiamond, arrowhead=none, style=dashed, taillabel="1", headlabel="*"])
    end
  end

  test "names the resources a diagram relates to but doesn't draw, as outside it" do
    diagram = %EntityRelationship{
      entries: [
        %EntityRelationship.Entity{id: "MyApp.Accounts.User", label: "User", attributes: []},
        %EntityRelationship.Relationship{
          left: {"MyApp.Accounts.User", :exactly_one},
          right: {"MyApp.Sales.Order", :zero_or_more},
          identifying?: true
        }
      ]
    }

    dot = dot(diagram)

    assert dot =~ ~s("MyApp.Sales.Order" [shape=box, style="rounded,dashed")

    assert dot =~
             ~s(<FONT FACE="Courier">MyApp.Sales.Order</FONT><BR/><FONT POINT-SIZE="8"><I>outside this diagram</I></FONT>)

    refute dot =~ ~s("MyApp.Accounts.User" [shape=box)
  end

  test "draws an entity's attributes with their keys, and relationships in crow's foot" do
    diagram = %EntityRelationship{
      entries: [
        %EntityRelationship.Entity{
          id: "MyApp.User",
          label: "User",
          attributes: [
            %EntityRelationship.Attribute{type: "UUID", name: "id", is_primary_key?: true},
            %EntityRelationship.Attribute{type: "String？", name: "nickname", comment: "shown"}
          ]
        },
        %EntityRelationship.Relationship{
          left: {"MyApp.User", :exactly_one},
          right: {"MyApp.Post", :zero_or_more},
          identifying?: false,
          label: "posts"
        }
      ]
    }

    dot = dot(diagram)

    assert dot =~
             ~s(<TD ALIGN="LEFT"><FONT FACE="Courier">UUID</FONT></TD><TD ALIGN="LEFT"><FONT FACE="Courier">id</FONT></TD><TD ALIGN="LEFT">PK</TD>)

    assert dot =~ ~s(<FONT FACE="Courier">nickname</FONT></TD><TD ALIGN="LEFT"> shown</TD>)

    assert dot =~
             ~s("MyApp.User" -> "MyApp.Post" [dir=both, arrowtail=teetee, arrowhead=crowodot, style=dashed, xlabel="posts"])
  end

  test "draws C4 boundaries as clusters around their elements, and relationships between them" do
    diagram = %C4{
      type: :c4_context,
      title: "",
      entries: [
        %C4.Boundary{
          type: :system_boundary,
          alias: "beam",
          label: "BEAM",
          entries: [
            %C4.Element{type: :system, external?: false, alias: "user", label: "User", description: "Resource"},
            %C4.Element{type: :system_db, external?: true, alias: "postgres", label: "Postgres"}
          ]
        },
        %C4.Relationship{type: :rel, from: "user", to: "postgres", label: "uses", technology: "SQL"}
      ]
    }

    dot = dot(diagram)

    assert dot =~ ~s(subgraph "cluster_beam" {)
    assert dot =~ ~s("user" [shape=box)
    assert dot =~ ~s("postgres" [shape=cylinder)
    assert dot =~ ~s("user" -> "postgres" [xlabel=<uses<BR/>[SQL]>];)
  end

  test "escapes what would break the DOT or its HTML labels" do
    diagram = %Class{
      entries: [
        %Class.Class{
          id: ~S(My"App\User),
          label: "<User & co>",
          members: [%Class.Field{name: ~s(a"b), type: "T"}]
        }
      ]
    }

    dot = dot(diagram)

    assert dot =~ ~S("My\"App\\User" [label=<)
    assert dot =~ "<B>&lt;User &amp; co&gt;</B>"
    assert dot =~ "T a&quot;b"
  end

  test "colours the diagram for a dark page" do
    diagram = %Class{entries: [%Class.Class{id: "A"}]}

    assert dot(diagram) =~ ~s(fontcolor="#111827")
    assert dot(diagram, theme: :dark) =~ ~s(fontcolor="#f0f0f0")
  end

  test "composes the diagrams the data modules build" do
    for diagram <- [
          Data.Class.for_domains([Domain]),
          Data.EntityRelationship.for_domains([Domain]),
          Data.Architecture.for_domains([Domain])
        ] do
      dot = dot(diagram)
      assert String.starts_with?(dot, "digraph {\n")
      assert String.ends_with?(dot, "}\n")
    end
  end
end
