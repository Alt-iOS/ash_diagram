defmodule AshDiagram.Graphviz do
  @moduledoc """
  Composes Graphviz [DOT](https://graphviz.org/doc/info/lang.html) for class,
  entity relationship and C4 diagrams, as an alternative to their Mermaid.

  Graphviz lays out a diagram of a few hundred resources in about a second, and
  draws it as plain SVG, where Mermaid measures every label in the browser's
  DOM and takes far longer. Clarity draws its diagrams with it.

  ## Options

  - `{:theme, :light | :dark}` - Colours for a light or dark page (default `:light`)
  """

  alias AshDiagram.C4
  alias AshDiagram.Class
  alias AshDiagram.EntityRelationship

  @type option() :: {:theme, :light | :dark}
  @type options() :: [option()]

  @doc """
  Composes the DOT for `diagram`.

  ## Examples

      iex> %AshDiagram.Class{
      ...>   entries: [%AshDiagram.Class.Class{id: "MyApp.User", label: "User"}]
      ...> }
      ...> |> AshDiagram.Graphviz.compose()
      ...> |> IO.iodata_to_binary()
      ...> |> String.contains?(~s("MyApp.User" [label=<))
      true

  """
  @spec compose(diagram :: Class.t() | EntityRelationship.t() | C4.t(), options :: options()) ::
          iodata()
  def compose(diagram, options \\ [])

  def compose(%Class{} = diagram, options) do
    colors = colors(options)
    {classes, relationships} = Enum.split_with(diagram.entries, &match?(%Class.Class{}, &1))

    graph(colors, "LR", [
      Enum.map(classes, &class_node(&1, colors)),
      outside_nodes(
        Enum.map(classes, & &1.id),
        Enum.flat_map(relationships, &[&1.left.class, &1.right.class]),
        colors
      ),
      Enum.map(relationships, &class_edge/1)
    ])
  end

  def compose(%EntityRelationship{} = diagram, options) do
    colors = colors(options)

    {entities, relationships} =
      Enum.split_with(diagram.entries, &match?(%EntityRelationship.Entity{}, &1))

    graph(colors, "LR", [
      Enum.map(entities, &entity_node(&1, colors)),
      outside_nodes(
        Enum.map(entities, & &1.id),
        Enum.flat_map(relationships, &[elem(&1.left, 0), elem(&1.right, 0)]),
        colors
      ),
      Enum.map(relationships, &entity_edge/1)
    ])
  end

  def compose(%C4{} = diagram, options) do
    colors = colors(options)

    # Left to right, so the boundaries stack: top to bottom, an application's
    # resources fall in one rank, a strip ten times as wide as it is high.
    graph(colors, "LR", [
      "  compound=true;\n",
      Enum.map(diagram.entries, &c4_entry(&1, colors, "  "))
    ])
  end

  # Text is set in Helvetica, and members in Courier, whose widths Graphviz
  # knows: in a font it doesn't, it guesses, and the browser's text overflows
  # the boxes drawn around it. A browser without Helvetica draws another,
  # wider sans-serif, but any monospace font is as wide as Courier.
  #
  # Edges are labelled with xlabel, placed once the graph is laid out: a label
  # would be laid out as a node of its own, taking Graphviz twenty times as
  # long over an application's relationships.
  @spec graph(colors :: map(), rankdir :: String.t(), body :: iodata()) :: iodata()
  defp graph(colors, rankdir, body) do
    [
      "digraph {\n",
      "  graph [rankdir=",
      rankdir,
      ", bgcolor=transparent, fontname=\"Helvetica\", fontcolor=\"",
      colors.text,
      "\", nodesep=0.3, ranksep=0.6];\n",
      "  node [shape=plain, fontname=\"Helvetica\", fontsize=10, fontcolor=\"",
      colors.text,
      "\", color=\"",
      colors.border,
      "\"];\n",
      "  edge [fontname=\"Helvetica\", fontsize=9, arrowsize=0.7, color=\"",
      colors.line,
      "\", fontcolor=\"",
      colors.muted,
      "\"];\n",
      body,
      "}\n"
    ]
  end

  @spec colors(options :: options()) :: map()
  defp colors(options) do
    case Keyword.get(options, :theme, :light) do
      :dark ->
        %{
          text: "#f0f0f0",
          muted: "#cbd5e1",
          border: "#9ca3af",
          line: "#94a3b8",
          fill: "#1f2937",
          header: "#374151",
          external: "#111827"
        }

      _light ->
        %{
          text: "#111827",
          muted: "#4b5563",
          border: "#6b7280",
          line: "#6b7280",
          fill: "#ffffff",
          header: "#e5e7eb",
          external: "#f3f4f6"
        }
    end
  end

  # Class diagrams

  @spec class_node(class :: Class.Class.t(), colors :: map()) :: iodata()
  defp class_node(%Class.Class{} = class, colors) do
    {methods, fields} = Enum.split_with(class.members, &match?(%Class.Method{}, &1))

    title =
      case class.generic do
        nil -> class.label || class.id
        generic -> [class.label || class.id, "<", generic, ">"]
      end

    node(class.id, [
      table_open(colors),
      header_row(title, colors),
      member_rows(Enum.map(fields, &field_text/1)),
      member_rows(Enum.map(methods, &method_text/1)),
      "</TABLE>"
    ])
  end

  @spec member_rows(texts :: [iodata()]) :: iodata()
  defp member_rows([]), do: []

  defp member_rows(texts) do
    [
      "<HR/>",
      Enum.map(texts, &["<TR><TD ALIGN=\"LEFT\">", code(&1), "</TD></TR>"])
    ]
  end

  @spec field_text(field :: Class.Field.t()) :: iodata()
  defp field_text(%Class.Field{} = field) do
    [
      visibility(field.visibility),
      case field.type do
        nil -> []
        type -> [member_type(type), " "]
      end,
      field.name
    ]
  end

  @spec method_text(method :: Class.Method.t()) :: iodata()
  defp method_text(%Class.Method{} = method) do
    [
      visibility(method.visibility),
      method.name,
      "(",
      Enum.map_intersperse(method.arguments, ", ", fn
        {name, nil} -> name
        {name, type} -> [member_type(type), " ", name]
      end),
      ")",
      case method.type do
        nil -> []
        type -> [" : ", member_type(type)]
      end
    ]
  end

  @spec visibility(visibility :: Class.Member.visibility() | nil) :: iodata()
  defp visibility(nil), do: []
  defp visibility(visibility), do: Class.Member.compose_visibility(visibility)

  @spec member_type(type :: Class.Member.type()) :: iodata()
  defp member_type({:generic, name, inner}), do: [name, "<", member_type(inner), ">"]
  defp member_type(type), do: type

  @class_arrows %{
    inheritance: "empty",
    realization: "empty",
    composition: "diamond",
    aggregation: "odiamond",
    association: "vee",
    dependency: "vee"
  }

  @spec class_edge(relationship :: Class.Relationship.t()) :: iodata()
  defp class_edge(%Class.Relationship{left: left, right: right} = relationship) do
    [
      "  ",
      quote_id(left.class),
      " -> ",
      quote_id(right.class),
      " [dir=both, arrowtail=",
      Map.get(@class_arrows, left.type, "none"),
      ", arrowhead=",
      Map.get(@class_arrows, right.type, "none"),
      if(relationship.style == :dashed, do: ", style=dashed", else: []),
      attribute("taillabel", left.cardinality),
      attribute("headlabel", right.cardinality),
      attribute("xlabel", relationship.label),
      "];\n"
    ]
  end

  # Entity relationship diagrams

  @spec entity_node(entity :: EntityRelationship.Entity.t(), colors :: map()) :: iodata()
  defp entity_node(%EntityRelationship.Entity{} = entity, colors) do
    node(entity.id, [
      table_open(colors),
      header_row(entity.label || entity.id, colors, 3),
      case entity.attributes do
        nil -> []
        [] -> []
        attributes -> ["<HR/>", Enum.map(attributes, &attribute_row/1)]
      end,
      "</TABLE>"
    ])
  end

  @spec attribute_row(attribute :: EntityRelationship.Attribute.t()) :: iodata()
  defp attribute_row(%EntityRelationship.Attribute{} = attribute) do
    keys =
      [
        attribute.is_primary_key? && "PK",
        attribute.is_foreign_key? && "FK",
        attribute.is_unique_key? && "UK"
      ]
      |> Enum.filter(& &1)
      |> Enum.join(",")

    [
      "<TR><TD ALIGN=\"LEFT\">",
      code(attribute.type),
      "</TD><TD ALIGN=\"LEFT\">",
      code(attribute.name),
      "</TD><TD ALIGN=\"LEFT\">",
      escape(keys),
      case attribute.comment do
        nil -> []
        comment -> [" ", escape(comment)]
      end,
      "</TD></TR>"
    ]
  end

  # Crow's foot ends: Graphviz draws the first shape nearest the node.
  @cardinality_arrows %{
    zero_or_one: "teeodot",
    exactly_one: "teetee",
    zero_or_more: "crowodot",
    one_or_more: "crowtee"
  }

  @spec entity_edge(relationship :: EntityRelationship.Relationship.t()) :: iodata()
  defp entity_edge(%EntityRelationship.Relationship{} = relationship) do
    {left, left_cardinality} = relationship.left
    {right, right_cardinality} = relationship.right

    [
      "  ",
      quote_id(left),
      " -> ",
      quote_id(right),
      " [dir=both, arrowtail=",
      Map.fetch!(@cardinality_arrows, left_cardinality),
      ", arrowhead=",
      Map.fetch!(@cardinality_arrows, right_cardinality),
      if(relationship.identifying?, do: [], else: ", style=dashed"),
      attribute("xlabel", relationship.label),
      "];\n"
    ]
  end

  # C4 diagrams

  @spec c4_entry(entry :: C4.entry(), colors :: map(), indent :: iodata()) :: iodata()
  defp c4_entry(%C4.Boundary{} = boundary, colors, indent) do
    [
      indent,
      "subgraph ",
      quote_id(["cluster_", boundary.alias]),
      " {\n",
      indent,
      "  label=<<B>",
      escape(boundary.label),
      "</B>>; labeljust=l; style=\"rounded,dashed\"; color=\"",
      colors.border,
      "\";\n",
      Enum.map(boundary.entries, &c4_entry(&1, colors, [indent, "  "])),
      indent,
      "}\n"
    ]
  end

  defp c4_entry(%C4.Element{} = element, colors, indent) do
    shape =
      cond do
        element.type in [:system_db, :container_db, :component_db] -> "cylinder"
        element.type in [:system_queue, :container_queue, :component_queue] -> "cds"
        element.type == :person -> "egg"
        true -> "box"
      end

    [
      indent,
      quote_id(element.alias),
      " [shape=",
      shape,
      ", style=\"rounded,filled\", fillcolor=\"",
      if(element.external?, do: colors.external, else: colors.fill),
      "\", margin=\"0.15,0.08\", label=<<B>",
      escape(element.label),
      "</B>",
      case element.description do
        nil ->
          []

        description ->
          ["<BR/><FONT POINT-SIZE=\"8\">", escape(description), "</FONT>"]
      end,
      ">];\n"
    ]
  end

  defp c4_entry(%C4.Relationship{} = relationship, _colors, indent) do
    [
      indent,
      quote_id(relationship.from),
      " -> ",
      quote_id(relationship.to),
      " [",
      if(relationship.type == :bi_rel, do: "dir=both, ", else: []),
      "xlabel=<",
      escape(relationship.label),
      case relationship.technology do
        nil -> []
        technology -> ["<BR/>[", escape(technology), "]"]
      end,
      ">];\n"
    ]
  end

  defp c4_entry(_entry, _colors, _indent), do: []

  # Shared

  # A diagram of some resources (a domain's, say) relates them to others it
  # doesn't draw: those are named and marked as outside it.
  @spec outside_nodes(drawn :: [iodata()], related :: [iodata()], colors :: map()) :: iodata()
  defp outside_nodes(drawn, related, colors) do
    drawn = MapSet.new(drawn, &IO.iodata_to_binary/1)

    related
    |> Enum.map(&IO.iodata_to_binary/1)
    |> Enum.uniq()
    |> Enum.reject(&MapSet.member?(drawn, &1))
    |> Enum.map(fn id ->
      [
        "  ",
        quote_id(id),
        ~s( [shape=box, style="rounded,dashed", margin="0.1,0.04", fontcolor="),
        colors.muted,
        "\", label=<",
        code(id),
        "<BR/><FONT POINT-SIZE=\"8\"><I>outside this diagram</I></FONT>>];\n"
      ]
    end)
  end

  @spec node(id :: iodata(), label :: iodata()) :: iodata()
  defp node(id, label), do: ["  ", quote_id(id), " [label=<", label, ">];\n"]

  @spec table_open(colors :: map()) :: iodata()
  defp table_open(colors) do
    [
      ~s(<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="3" COLOR="),
      colors.border,
      "\" BGCOLOR=\"",
      colors.fill,
      "\">"
    ]
  end

  @spec header_row(title :: iodata(), colors :: map(), columns :: pos_integer()) :: iodata()
  defp header_row(title, colors, columns \\ 1) do
    [
      "<TR><TD COLSPAN=\"",
      Integer.to_string(columns),
      "\" BGCOLOR=\"",
      colors.header,
      "\"><B>",
      escape(title),
      "</B></TD></TR>"
    ]
  end

  @spec code(text :: iodata()) :: iodata()
  defp code(text), do: ["<FONT FACE=\"Courier\">", escape(text), "</FONT>"]

  @spec attribute(name :: String.t(), value :: iodata() | nil) :: iodata()
  defp attribute(_name, nil), do: []
  defp attribute(_name, []), do: []
  defp attribute(name, value), do: [", ", name, "=", quote_id(value)]

  @spec quote_id(id :: iodata()) :: iodata()
  defp quote_id(id) do
    escaped =
      id
      |> IO.iodata_to_binary()
      |> String.replace("\\", "\\\\")
      |> String.replace(~S("), ~S(\"))

    [?", escaped, ?"]
  end

  @spec escape(text :: iodata()) :: iodata()
  defp escape(text) do
    text
    |> IO.iodata_to_binary()
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~S("), "&quot;")
  end
end
