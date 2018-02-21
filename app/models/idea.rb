class Idea < ApplicationRecord
  has_many :pledges, as: :item
  belongs_to :user
  has_many :events
  belongs_to :converted, polymorphic: true, optional: true
  belongs_to :proposer, polymorphic: true, optional: true
  belongs_to :parent, polymorphic: true, optional: true
  belongs_to :proposalstatus, optional: true
  belongs_to :ideatype
  has_many :additionaltimes, as: :item
  has_many :comments, as: :item, dependent: :destroy
  validates :ideatype, :proposer_type, :proposer_id, :presence => true, :if => :active_or_find_type? 
  validates :name, :short_description, :proposal_text,  presence: true, if: :active_or_name_and_info?
  # validates :timeslot_undetermined, inclusion: { in: [ true, false ]}, if: :active_or_when?
  validates :start_at, :end_at, presence: true, if: :determined_time?
  validates :points_needed,  presence: true, if: :active_or_points?
  validates :slug, presence: true, if: :active?
  accepts_nested_attributes_for :additionaltimes, reject_if: proc {|x| x['start_at'].blank? || x['end_at'].blank? }, allow_destroy: true

  has_many :activities, as: :item
  has_many :notifications, as: :item
  
  extend FriendlyId
  friendly_id :name, use: [:slugged, :finders]

  mount_uploader :image, ImageUploader
  before_save :update_image_attributes
  scope :between, -> (start_time, end_time) { 
    where( [ "(start_at >= ?  AND  end_at <= ?) OR ( start_at >= ? AND end_at <= ? ) OR (start_at >= ? AND start_at <= ?)  OR (start_at < ? AND end_at > ? )",
    start_time.to_date.at_midnight.to_s(:db), end_time.to_date.end_of_day.to_s(:db), start_time.to_date.at_midnight.to_s(:db), end_time.to_date.end_of_day.to_s(:db), 
    start_time.to_date.at_midnight.to_s(:db), end_time.to_date.end_of_day.to_s(:db), start_time.to_date.at_midnight.to_s(:db), end_time.to_date.end_of_day.to_s(:db)])
  }
  scope :timed, -> () { where(timeslot_undetermined: false)}
  scope :active, ->() { where(status: 'active')}
  scope :back_room, ->() {where("room_needed in (2,3)")}
  scope :needing_to_be_published,  ->() { where(notified: :true).where(converted_id: nil)}
  scope :converted, -> () { where("converted_id is not null")}
  scope :unconverted, -> () { where(converted_id: nil)}
  
  def as_json(options = {})
    {
      :id => self.id,
      :title =>  self.name,
      :description => self.short_description || "",
      :start => calendar_start_at.nil? ? nil : calendar_start_at.localtime.strftime('%Y-%m-%d %H:%M:00'),
      :end => end_at.nil? ? nil : end_at.localtime.strftime('%Y-%m-%d %H:%M:00'),
      :allDay => false, 
      :recurring => false,
      :temps => self.points_needed,
      class: 'proposal',
      :url => Rails.application.routes.url_helpers.idea_path(self.slug)
    } 
  end 

  def calendar_start_at
    start_at - 1.hour
  end

  def converted?
    !events.empty?
  end

  def root_comment
    self
  end

  def discussion
    [pledges, comments].flatten.compact
  end
  

  def add_to_activity_feed
    if active?
      Activity.create(user: user, item: self, description: ideatype_id == 3 ? 'requested' : 'proposed')
    end
  end

  def active_or_find_type?
    status.include?('find_type') || active? && ideatype_id != 4
  end

  def active_or_when?
    status.include?('when') || active?
  end

  def active_or_points?
    status.include?('points') || active?
  end

  def determined_time?
    (timeslot_undetermined == false && !timeslot_undetermined.nil? ) && ideatype_id == 1 && (status.include?('points') || active?)
  end

  def active_or_name_and_info?
    status.include?('name_and_info') || active?
  end

  def should_generate_new_friendly_id?
    active?
  end

  def has_enough?
    pledged >= points_needed
  end

  def active?
    status == 'active'
  end

  def start_at_date
    start_at.nil? ? nil : start_at.strftime('%Y-%m-%d')
  end

  def end_at_date
    end_at.nil? ? nil : end_at.strftime('%Y-%m-%d')
  end

  def points_still_needed
    points_needed -  pledges.select(&:persisted?).sum(&:pledge)  
  end

  def points_still_needed_except(pledge)
    points_needed - pledges.select(&:persisted?).select{|x| x != pledge}.sum(&:pledge)
  end

  def max_for_user(user, pledge)
    [user.available_balance, (points_needed * 0.9), pledges.select(&:persisted?).map(&:user).delete_if{|x| x == user}.uniq.size >= 2 ? points_still_needed_except(pledge) :
     points_still_needed_except(pledge) - 1 ].min.to_i
  end

  def pledged
    pledges.select(&:persisted?).sum(&:pledge)
  end

  def proposers
    if proposer_type == Group
      [user, proposer.members.map(&:user)].uniq
    else
      [user, proposer].uniq
    end
  end
  
  def notify_if_enough
  
    if pledged >= points_needed
      if self.notified != true
        begin
          IdeaMailer.proposal_for_review(self).deliver_now
          update_attribute(:notified, true)
        rescue
          die
          notified = false
        end
      end
    end
  end

  private

  def update_image_attributes

    if image.present? && image?

      if image.file.exists?
        self.image_content_type = image.file.content_type
        self.image_size = image.file.size
        self.image_width, self.image_height = `identify -format "%wx%h" #{image.file.path}`.split(/x/) rescue nil
      end
    end
  end

end
