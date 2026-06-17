class ClientsController < AuthenticatedController
  before_action :require_write_access!, only: %i[create update destroy]
  before_action :set_client, only: %i[show edit update destroy]

  def index
    @clients = current_organization.clients
                                   .includes(:job_roles, :shortlists)
                                   .order(:name)
  end

  def show; end

  def new
    @client = current_organization.clients.build
  end

  def create
    @client = current_organization.clients.build(client_params)
    if @client.save
      redirect_to clients_path, notice: "Client \"#{@client.name}\" created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @client.update(client_params)
      redirect_to clients_path, notice: "Client updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @client.name
    @client.destroy
    redirect_to clients_path, notice: "\"#{name}\" deleted."
  end

  private

  def set_client
    @client = current_organization.clients.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to clients_path, alert: "Client not found."
  end

  def client_params
    params.require(:client).permit(:name, :contact_email, :logo_url)
  end
end
