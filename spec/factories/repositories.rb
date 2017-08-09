FactoryGirl.define do
  factory :repository do
    sequence(:name) { |n| "Repository #{n}" }

    sequence(:external_url) { |n| "https://updates.suse.com/suse/repository_#{n}" }
    sequence(:distro_target) { |n| "i586-#{n}" }
    sequence(:enabled) { true }
    sequence(:autorefresh) { true }

    after(:build) do |obj|
      obj.local_path = obj.make_local_path(obj.external_url)
    end

    trait :authenticated do
      sequence(:url) { "/#{FFaker.letterify('?????')}" }
    end

    trait :with_products do
      transient do
        products_count 1
      end

      after :create do |repository, evaluator|
        evaluator.products_count.times do
          repository.services << create(:service)
        end
      end
    end
  end
end
