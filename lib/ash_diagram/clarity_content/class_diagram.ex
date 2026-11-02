with {:module, Clarity.Content} <- Code.ensure_loaded(Clarity.Content) do
  defmodule AshDiagram.ClarityContent.ClassDiagram do
    @moduledoc """
    Content provider for Class diagrams of Ash applications and domains.
    """

    @behaviour Clarity.Content

    alias AshDiagram.Data.Class
    alias Clarity.Vertex
    alias Clarity.Vertex.Ash.Domain
    alias Clarity.Vertex.Ash.Resource

    @impl Clarity.Content
    def name, do: "Class Diagram"

    @impl Clarity.Content
    def description, do: "Class diagram showing resource structure and relationships"

    @impl Clarity.Content
    def applies?(%Vertex.Application{app: app}, _lens) do
      app
      |> Ash.Info.domains()
      |> case do
        [] -> false
        _domains -> true
      end
    end

    def applies?(%Domain{}, _lens), do: true
    def applies?(%Resource{}, _lens), do: true
    def applies?(_vertex, _lens), do: false

    @impl Clarity.Content
    def render_static(%Vertex.Application{app: app}, _lens) do
      [app]
      |> Class.for_applications(show_private?: true)
      |> graphviz()
    end

    def render_static(%Domain{domain: domain}, _lens) do
      [domain]
      |> Class.for_domains(show_private?: true)
      |> graphviz()
    end

    def render_static(%Resource{resource: resource}, _lens) do
      [resource]
      |> Class.for_resources(show_private?: true)
      |> graphviz()
    end

    # Graphviz lays out hundreds of resources in about a second; Mermaid took
    # far longer, and stacked them out of reach.
    @spec graphviz(diagram :: AshDiagram.t()) :: Clarity.Content.static_content()
    defp graphviz(diagram) do
      {:viz,
       fn %{theme: theme} ->
         diagram |> AshDiagram.Graphviz.compose(theme: theme) |> IO.iodata_to_binary()
       end}
    end
  end
end
