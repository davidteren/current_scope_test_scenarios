module Api
  module V1
    class ItemsController < Api::BaseController
      def index
        render json: scope_for(Item).order(:id)
      end

      def show
        render json: item
      end

      def create
        record = Item.create!(item_params.merge(user: current_user))
        render json: record, status: :created
      end

      def destroy
        item.destroy!
        head :no_content
      end

      def publish
        item.update!(published: true)
        render json: item
      end

      private

      def item
        @item ||= Item.find(request.path_parameters[:id])
      end

      def current_scope_record
        item if request.path_parameters[:id]
      end

      def item_params
        params.expect(item: [ :name ])
      end
    end
  end
end
