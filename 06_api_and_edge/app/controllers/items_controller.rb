# Minimal HTML controller — used to compare AccessDenied behavior HTML vs JSON.
class ItemsController < ApplicationController
  def index
    @items = scope_for(Item)
  end
end
