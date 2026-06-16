Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Login / logout
  get    "/login",   to: "sessions#new",     as: :login
  delete "/session", to: "sessions#destroy", as: :logout

  # Google OAuth
  namespace :auth do
    get    "google/login",     to: "google#login",       as: :google_login
    get    "google/connect",   to: "google#connect",     as: :google
    get    "google/callback",  to: "google#callback",    as: :google_callback
    delete "google",           to: "google#disconnect",  as: :google_disconnect
  end

  get  "settings",             to: "settings#show",                as: :settings
  patch "settings/availability", to: "settings#update_availability", as: :update_availability_settings

  root "video_analyses#index"
  get "dashboard", to: "dashboard#index", as: :dashboard
  resources :video_analyses, only: %i[new create show index destroy] do
    member do
      post  :reanalyse
      get   :transcript
      patch :link_video
    end
  end
  resources :cv_analyses, only: %i[create show index destroy] do
    collection do
      post :bulk_create
    end
    member do
      post :reanalyse
      get  :extracted_text
    end
  end
  resources :job_roles do
    member do
      post :extract_requirements
    end
  end

  # Candidate pipeline
  resources :candidates, only: %i[index show destroy update] do
    member do
      scope :pipeline do
        post :advance,         to: "candidates/pipeline#advance"
        post :reject,          to: "candidates/pipeline#reject"
        post :revert,          to: "candidates/pipeline#revert"
        post :final_interview, to: "candidates/pipeline#final_interview"
        post :not_invited,     to: "candidates/pipeline#not_invited"
        post :hire,            to: "candidates/pipeline#hire"
        post :offer_declined,  to: "candidates/pipeline#offer_declined"
        post :not_selected,    to: "candidates/pipeline#not_selected"
        post :confirm_outcome, to: "candidates/pipeline#confirm_outcome"
        post :toggle_no_show,  to: "candidates/pipeline#toggle_no_show"
      end
      scope :communications do
        get   :send_invite_email,   to: "candidates/communications#send_invite_email"
        get   :send_followup_email, to: "candidates/communications#send_followup_email"
        patch :update_email,        to: "candidates/communications#update_email"
        patch :update_timeline,     to: "candidates/communications#update_timeline"
        post  :sync_calendar,       to: "candidates/communications#sync_calendar"
      end
    end
  end

  # Public candidate intake form (no auth)
  get  "/i/:token", to: "intake#show",   as: :candidate_intake
  post "/i/:token", to: "intake#submit", as: :candidate_intake_submit

  # Recruiter shortlist management (authenticated)
  resources :shortlists do
    resources :shortlist_items, only: %i[create update destroy], shallow: true
  end

  # Public shared link (no auth)
  scope "/s" do
    get   "/:token",                      to: "shared_shortlists#show",      as: :shared_shortlist
    post  "/:token/verify",               to: "shared_shortlists#verify",    as: :verify_shared_shortlist
    get   "/:token/items/:id",            to: "shared_shortlists#show_item", as: :shared_shortlist_item
    patch "/:token/items/:id/feedback",   to: "shared_shortlists#feedback",  as: :shared_shortlist_feedback
    patch "/:token/items/:id/no_show",    to: "shared_shortlists#no_show",   as: :shared_shortlist_no_show
  end
end
