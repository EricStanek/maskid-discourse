# frozen_string_literal: true

Maskid::Engine.routes.draw do
  get "/start" => "link#start"
  get "/return" => "link#return"
  post "/webhook" => "link#webhook"
  delete "/unlink" => "link#unlink"
end

Discourse::Application.routes.draw { mount ::Maskid::Engine, at: "maskid" }
