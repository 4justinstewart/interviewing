class PaidGigReplacementsController < ApplicationController
  before_action :validate_routable, only: [:new]

  def new
    paid_gig
    @deliverable_kinds = Deliverable::KINDS

    render './view'
  end

  def create
    replacement_paid_gig = paid_gig.replace!(paid_gig_params, deliverables_params)
    PaidGigSnapshotsWorker.perform_async(replacement_paid_gig.id)

    redirect_to new_paid_gig_replacement_path(paid_gig_id: replacement_paid_gig.id), notice: 'The gig has been successfully replaced 🔥'
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: new_paid_gig_replacement_path(paid_gig_id: paid_gig.id), alert: "Error(s) replacing gig: #{e.record.errors.full_messages.to_sentence}"
  rescue ActiveRecord::RecordNotUnique
    redirect_back fallback_location: new_paid_gig_replacement_path(paid_gig_id: paid_gig.id), alert: 'Error replacing gig: Multiple deliverables of the same kind are not allowed.'
  end

  private

  def paid_gig
    @paid_gig ||= PaidGig.find(params[:paid_gig_id])
  end

  def validate_routable
    unless paid_gig.in_progress?
      redirect_to root_path, alert: "This gig is #{paid_gig.aasm_state.humanize}. Only gigs that are contractually in progress can be replaced. Sorry!"
    end
  end

  def paid_gig_params
    params.require(:paid_gig).permit(
      :cost,
      :markup,
      :photos_to_upload,
      :blogs_to_upload,
      :videos_to_upload,
      :mixed_media_to_upload,
      :minimum_child_content_submission_count,
      :required_feed_posts,
      :required_story_posts
    )
  end

  def deliverables_params
    params.require(:paid_gig).permit(deliverables_attributes: [:kind, :quantity, :_destroy])
  end
end
