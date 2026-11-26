module Api
  class ItemBlocksController < InventoryBaseController
    #-----------------------------------------------------------------------------
    def index
      scope = owned_edges.includes(:blocker, :blocked)
      # Resolve filter endpoints within the owner scope, including empty/stale IDs.
      %i[blocker_id blocked_id].each do |field|
        next unless params.key?(field)
        value = params[field]
        unless value.is_a?(String) && value.match?(/\A[1-9]\d*\z/) && valid_id?(value.to_i)
          render json: { error: "invalid_filter" }, status: :bad_request
          return
        end
        scope = scope.where(field => current_user.items.find(value).id)
      end
      result = page(scope)
      return if performed?
      rows, cursor = result
      render json: { item_blocks: rows.map { |edge| edge_json(edge) }, next_after_id: cursor }
    end

    #-----------------------------------------------------------------------------
    def show
      render json: { item_block: edge_json(owned_edges.find(params[:id])) }
    end

    #-----------------------------------------------------------------------------
    def create
      input = json_input(:item_block, %w[blocker_id blocked_id])
      return if performed?
      unless valid_id?(input[:blocker_id]) && valid_id?(input[:blocked_id])
        return render json: { error: "validation_failed" }, status: :unprocessable_entity
      end
      edge = nil
      created = false
      current_user.with_lock do
        blocker = current_user.items.find(input[:blocker_id])
        blocked = current_user.items.find(input[:blocked_id])
        edge = current_user.item_blocks.find_by(blocker_id: blocker.id, blocked_id: blocked.id)
        unless edge
          edge = current_user.item_blocks.create!(blocker: blocker, blocked: blocked)
          created = true
        end
      end
      render json: { item_block: edge_json(edge) }, status: created ? :created : :ok
    rescue ActiveRecord::InvalidForeignKey
      # A concurrent endpoint deletion must not leave an orphan or recreate an item.
      not_found
    end

    #-----------------------------------------------------------------------------
    def destroy
      edge = owned_edges.find(params[:id])
      current_user.with_lock { edge.destroy! }
      render json: { deleted: edge.id }
    end

    private

    #-----------------------------------------------------------------------------
    def owned_edges
      # Hide corrupt legacy links as well as ordinary foreign-owned edges.
      ids = current_user.items.select(:id)
      current_user.item_blocks.where(blocker_id: ids, blocked_id: ids)
    end

    #-----------------------------------------------------------------------------
    def edge_json(edge)
      { id: edge.id, blocker_id: edge.blocker_id, blocked_id: edge.blocked_id,
        blocker: { id: edge.blocker.id, title: edge.blocker.title, done: edge.blocker.done? },
        blocked: { id: edge.blocked.id, title: edge.blocked.title, done: edge.blocked.done? },
        active: !edge.blocker.done? }
    end
  end
end
