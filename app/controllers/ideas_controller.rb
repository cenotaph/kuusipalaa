class IdeasController < ApplicationController

  before_action :authenticate_user!, except: [:index, :show]

  def calendar
    #  build month
    @times = []
    start = params['start'].to_date
    enddate = params['end'].to_date
    (start..enddate).each do |day|
      next if day < Time.now.utc.to_date
      @times << {title: t(:choose) + l(day.to_date, format: :short), day: day, start: "#{day} 00:00:01".to_s, end:  "#{day} 23:59:59".to_s, allDay: true, recurring: false, url: "choose_day/#{day.to_s}"}

    end

    #  add existing instances and probably proposals too
    @times += Instance.published.between(params['start'], params['end']) if (params['start'] && params['end'])
    respond_to do |format|
      format.html # index.html.erb
      format.json { render :json => @times.flatten.uniq }
    end
  end

  def create
    if params[:step1] == 'event'
      @idea = Idea.create(status: 'building', ideatype_id: 1, proposer: current_user, user: current_user)
      redirect_to idea_build_index_path(idea_id: @idea.id)
    elsif params[:step1] == 'installation'
      @idea = Idea.create(status: 'building', ideatype_id: 2, proposer: current_user, user: current_user)
      redirect_to idea_thing_index_path(idea_id: @idea.id)
    elsif params[:step1] == 'request'
      @idea = Idea.create(status: 'building', ideatype_id: 3, proposer: current_user, user: current_user)
      redirect_to idea_request_index_path(idea_id: @idea.id)
    end
  end

  def index
    @ideas = Idea.active.order(updated_at: :desc)
  end

  def new
    @idea = Idea.new(status: 'building')
  end

  def publish_event
    @idea = Idea.friendly.find(params[:id])
    fill_collection
    if @idea.converted?
      redirect_to @idea.events.first
    else
      if @idea.has_enough? && @idea.proposers.include?(current_user)
        @event = Event.new(idea: @idea, place_id: 2, primary_sponsor: @idea.proposer, cost_euros: @idea.price_public, cost_bb: @idea.price_stakeholders, 
          translations: [Event::Translation.new(locale: I18n.locale, name: @idea.name, description: @idea.proposal_text)])
        # if @idea.timeslot_undetermined == true
          
        # else
          @event.instances << Instance.new(start_at: @idea.start_at, end_at: @idea.end_at, price_public: @idea.price_public, price_stakeholders: @idea.price_stakeholders, 
            room_needed: @idea.room_needed, allow_others: @idea.allow_others, place_id: 2, translations: [Instance::Translation.new(locale: I18n.locale,
              name: @idea.name, description: @idea.proposal_text)])
        # end
        unless @idea.additionaltimes.empty?
          @idea.additionaltimes.sort_by(&:start_at).each do |at|
            @event.instances << Instance.new(start_at: at.start_at, end_at: at.end_at, price_public: @idea.price_public, price_stakeholders: @idea.price_stakeholders,
              room_needed: @idea.room_needed, allow_others: @idea.allow_others, place_id: 2, translations: [Instance::Translation.new(locale: I18n.locale,
            name: @idea.name, description: @idea.proposal_text)])
          end
        end
      
      else
        flash[:error]= t(:not_enough_points_yet, count: @idea.points_still_needed)
        redirect_to @idea
      end
    end
  end

  def show
    @idea = Idea.friendly.find(params[:id])
    if user_signed_in?
      fill_collection
      if current_user.pledges.unconverted.where(item: @idea).empty?
        @pledge = @idea.pledges.build
      else
        # flash[:notice] = 'You already have an unspent pledge towards this proposal. You can edit or delete it but you cannot create a new one.'
        @pledge = current_user.pledges.unconverted.find_by(item: @idea)
      end 
    end 
    set_meta_tags title: @idea.name
    if @idea.status != 'active' && @idea.status != 'converted'
      flash[:error] = t(:idea_not_published_yet)
      redirect_to ideas_path
    end
  end

end