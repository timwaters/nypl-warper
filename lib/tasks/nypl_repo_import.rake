namespace :map do
  namespace :repo do

    #creates a map object from an item
    #optionally pass in image_id if you know it
    def get_map(item, uuid, image_id=nil)
      title = item["titleInfo"].select{|a|a["usage"]=="primary"}.last["title"]["$"]
      extra = item["note"].detect{|a| a["type"]=="statement of responsibility"} if item["note"]
      extra_title = extra.nil? ? "" : " / " + extra["$"]
      title = title + extra_title

      #relatedItem for :
      parent_uuid = item["relatedItem"]["identifier"].detect{|a| a["type"]=="uuid"}["$"]
      description = "From " + item["relatedItem"]["titleInfo"]["title"]["$"]
      
      #go into layers to find:
      client = NyplRepo::Client.new(REPO_CONFIG[:token])
      
      nypl_digital_id = image_id || client.get_image_id(parent_uuid, uuid)

      map = Map.new(:title => title, :description => description,
                    :uuid => uuid, :parent_uuid => parent_uuid,
                    :nypl_digital_id => nypl_digital_id,
                    :status => :unloaded, :map_type=>:is_map, :mask_status => :unmasked)
      
      map
    end

    def get_layer(related_item)
      uuid = related_item["identifier"].detect{|a| a["type"]=="uuid"}["$"]
      title = related_item["titleInfo"]["title"]["$"]
      layer = Layer.new(:name => title, :uuid => uuid)

      layer
    end
    
    def get_layers(related_item)
      layers = []
      layers << get_layer(related_item) 
      if related_item["relatedItem"] && related_item["relatedItem"]["titleInfo"]
        layers << get_layers(related_item["relatedItem"])
      end

      layers
    end

    #saves a map if it's new and with associated layers to that map
    def save_map_with_layers(map, layers)
      ActiveRecord::Base.transaction do
        #1 save map
        #map.save if map.new_record?

        #2 save new  or get layers
        assign_layers = []
        layers.each do | layer |
          if Layer.exists?(:uuid => layer.uuid)
            #p "exist: " + layer.uuid
            assign_layers << Layer.find_by_uuid(layer.uuid)
          else
            #p "no exist, save as new "+layer.uuid
            #layer.save
            assign_layers << layer
          end
        end
        puts assign_layers.inspect
        #3 then set the map to the layer
        #map.layers << layers ?
      end #transaction

    end


    desc "imports a map and any associated layer based on a uuid environment variable"
    task(:import_map => :environment) do
      unless ENV["uuid"]
        puts "usage: rake map:repo:import_map uuid=uuid"
        break
      end
      uuid = ENV["uuid"]

      if Map.exists?(:uuid => uuid)
        map = Map.find_by_uuid(uuid)
        puts "Map #{map.id.to_s} with uuid #{uuid} exists."
        break
      end

      client = NyplRepo::Client.new(REPO_CONFIG[:token])
      item = client.get_mods_item(uuid)
      
      map = get_map(item, uuid)
      layers = get_layers(item["relatedItem"]) 
      layers.flatten! 
      
      puts layers.inspect
      puts map.inspect
      
      save_map_with_layers(map,layers)

  
    end #task



    desc "imports a layer / collection of maps, based on uuid of layer id"
    task(:import_layer => :environment) do
      unless ENV["uuid"]
        puts "usage: rake map:repo:import_layer uuid=uuid"
        break
      end
      uuid = ENV["uuid"]
      client = NyplRepo::Client.new(REPO_CONFIG[:token])
      map_items = client.get_capture_items(uuid, true, true)
      map_items.each do | map_item |
        item = client.get_mods_item(map_item["uuid"])

        if Map.exists?(:uuid => map_item["uuid"])
          map = Map.find_by_uuid(map_item["uuid"])
        else
          map = get_map(item, map_item["uuid"], map_item["imageID"])
        end

        layers = get_layers(item["relatedItem"]) 
        layers.flatten! 
        
        save_map_with_layers(map,layers)
      end

    end



    desc "Imports new maps (with highreslinks and imageids) and associated layers from a date to a date.  Date to be in YYYY-MM-DD"
    task(:import_latest => :environment) do
      unless ENV["since"] && ENV["until"]
        puts "usage: rake map:repo:import_map since=date until=date"
        break
      end
      since = ENV["since"] 
      untildate = ENV["until"]
      client = NyplRepo::Client.new(REPO_CONFIG[:token])
      maps = client.get_items_since("%22Map%20Division%22&field=physicalLocation", since, untildate)
    
      maps.each do | map |
      next if map["highResLink"].nil? ||  map["imageID"].nil?
        puts map.inspect
      end

    end

  end
end
