class PaidGig < ApplicationRecord
  # opts:
  # cost_in_cents
  # markup_in_cents
  # photos_to_post
  # stories_to_post
  # photos_to_upload
  # blogs_to_upload
  # videos_to_upload
  # mixed_media_to_upload
  # minimum_child_content_submission_count
  #
  # updated_deliverables:
  # DEPRECATED - Replacement
  def replace!(opts, updated_deliverables = nil) # rubocop:disable Metrics/AbcSize
    opts.merge!(
      is_currently_replacing: true,
      last_viewed_at: self.last_viewed_at,
      shipping_address_id: self.shipping_address_id,
      campaign_id: self.campaign_id,
      user_id: self.user_id,
      due_on: self.due_on,
      answers: self.answers,
      metadata: { admin_notes: "Replaces PaidGig: #{self.id}" },
      expires_at: self.expires_at,
      unviewed_events_count: self.unviewed_events_count,
      accepted_story_posts_count: self.accepted_story_posts_count,
      campaign_creator_match_id: self.campaign_creator_match_id
    )

    self.class.transaction do
      replacement = self.class.new(opts)
      replacement.save!

      replacement.accept!

      if updated_deliverables.present?
        replacement.update!(updated_deliverables)
      else
        self.deliverables.each do |deliverable|
          replacement.deliverables << deliverable.dup
        end
      end

      # we need a reference to this for swap matching logic below before we
      # blow away the swap association directly below.
      swap_match_ids = self.swap_matches.ids
      flagged_swap_match_ids = self.flagged_swap_matches.ids

      # migrate has_one associated objects
      [:snailmail_shipment, :support_conversation,
       :merchant_conversation, :note].each do |association_name|
        replacement.send("#{association_name}=", self.send(association_name))
      end

      # the record ids that might appear in multiple scopes need to be
      # cached in memory before re-assigning the records or the migraiton
      # of records from earlier scope will prevent lookup on a later scope
      # from finding the already migrated record
      has_many_assocations = {
        content_submissions: self.content_submissions.ids,
        rejected_content_submissions: self.rejected_content_submissions.ids,
        accepted_content_submissions: self.accepted_content_submissions.ids
      }

      has_many_assocations.each do |assoc_name, ids|
        ContentSubmission.where(id: ids).each do |record|
          replacement.send(assoc_name) << record
        end
      end

      SwapMatch.where(id: swap_match_ids).each do |record|
        record.update(paid_gig_id: replacement.id)
        replacement.social_media_posted!(record)
        replacement.accepted_swap_matches << record
      end

      SwapMatch.where(id: flagged_swap_match_ids).each do |record|
        replacement.flagged_swap_matches << record
      end

      if replacement.upload_requirements_met? && replacement.post_requirements_met?
        replacement.requirements_met!
      end

      self.negotiations.each do |record|
        record.update(paid_gig_id: replacement.id)
      end

      # we need this reload so that we do not resave the old objects back to the original gig
      self.reload

      self.replaced_by = replacement
      self.save!

      replacement.is_currently_replacing = false
      replacement.save!

      self.cancel!(replacement: true)

      replacement
    end
  end
end
