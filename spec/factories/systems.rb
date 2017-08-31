FactoryGirl.define do
  factory :system do
    sequence(:login) { |n| "login#{n}" }
    sequence(:password) { |n| "password#{n}" }

    trait :with_activated_base_product do
      after :create do |system, _|
        system.services << FactoryGirl.create(:service) if system.services.blank?
        service = system.products.first.service
        FactoryGirl.create(:activation, system: system, service: service)
      end
    end
  end
end
