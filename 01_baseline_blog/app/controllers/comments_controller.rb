class CommentsController < ApplicationController
  # Host-side "nice 403 page" recipe (undocumented in the gem README):
  # a rescue_from declared in a subclass wins over the gem's bare `head :forbidden`.
  rescue_from CurrentScope::AccessDenied do |e|
    response.headers["X-Current-Scope-Reason"] = e.reason.to_s if e.reason
    render plain: "Sorry, you do not have permission (#{e.reason}).", status: :forbidden
  end

  before_action :set_comment, only: %i[ show edit update destroy ]

  # GET /comments
  def index
    @comments = scope_for(Comment)
  end

  # GET /comments/1
  def show
  end

  # GET /comments/new
  def new
    @comment = Comment.new
  end

  # GET /comments/1/edit
  def edit
  end

  # POST /comments
  def create
    @comment = Comment.new(comment_params)

    if @comment.save
      redirect_to @comment, notice: "Comment was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /comments/1
  def update
    if @comment.update(comment_params)
      redirect_to @comment, notice: "Comment was successfully updated.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /comments/1
  def destroy
    @comment.destroy!
    redirect_to comments_path, notice: "Comment was successfully destroyed.", status: :see_other
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    # Memoized: current_scope_record loads it before this callback runs.
    def set_comment
      @comment ||= Comment.find(params.expect(:id))
    end

    # Record-level decisions (scoped roles) load the record for the resolver;
    # nil on collection actions declares "no record here".
    def current_scope_record
      set_comment if request.path_parameters[:id]
    end

    # 0.3.0 (#50/#65): with the record hook above declaring nil on collection
    # actions, naming the type lets a scoped-only subject open listed collection
    # reads (index), gated on scope_for(Comment).exists?.
    def current_scope_model
      Comment
    end

    # Only allow a list of trusted parameters through.
    def comment_params
      params.expect(comment: [ :post_id, :body ])
    end
end
