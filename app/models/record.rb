class Record < ApplicationRecord
  belongs_to :affiliate
  delegate :company, to: :affiliate, allow_nil: true
  has_many :record_service
  has_many :services, through: :record_service

  enum record_type: {grouping: 0, personal: 1}
  enum visit_type: {one_time_visit: 0, reusable_visit: 1,
                    one_time_abon: 2, automatic_abon: 3, dynamic_abon: 4}

  validates :name, presence: true
end