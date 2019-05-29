class AdActivation < ApplicationRecord
  state_machine_block do
    state :request_for_proposal, initial: true
    state :negotiation
    state :in_contract
    state :complete

    event :create_proposal_request

    event :accept_proposal do
      transitions from: :request_for_proposal, to: :negotiation
    end

    event :negotiate
    event :accept_negotiation
    event :request_contract_amendment

    event :agree_as_complete do
      transitions from: :in_contract, to: :complete, if: Proc.new { |activation| activation.both_parties_agreed_to_completed_terms? }

      transitions from: :in_contract, to: :in_contract do
        EmailToOtherParticipatingParty.new(opt).deliver_now
      end
    end
  end

  has_many :participating_parties
  has_many :messages

  private

  def both_parties_agreed_to_completed_terms?
    participating_parties.all? { |party| party.agreed_at.present? }
  end
end

class ParticipatingParty < ApplicationRecord
  belongs_to :ad_activation, optional: false

  def self.db_backed_attributes
    new.attributes.keys
  end
  # => [
    # 'id',             # uuid, primary key
    # 'agreed_at',      # datetime,
    # 'email',          # text, string
  # ]
end

class Message < ApplicationRecord; end
