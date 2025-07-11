# frozen_string_literal: true

require 'optparse'

namespace :cards do
  desc 'import card data - json_dir defaults to /netrunner-cards-json/v2/ if not specified.'

  def text_to_id(text)
    text.downcase
        .unicode_normalize(:nfd)
        .gsub(/\P{ASCII}/, '')
        # TODO(plural): Fix contractions to match javascript version.
        .gsub(/'s(\p{Space}|\z)/, 's\1')
        .split(/[\p{Space}\p{Punct}]+/)
        .reject { |s| s&.strip&.empty? }
        .join('_')
  end

  def load_multiple_json_files(path)
    cards = []
    Dir.glob(path) do |f|
      next if File.directory? f

      File.open(f) do |file|
        (cards << JSON.parse(File.read(file))).flatten!
      end
    end
    cards
  end

  def import_sides(sides_path)
    sides = JSON.parse(File.read(sides_path))
    sides.map! do |s|
      {
        id: s['id'],
        name: s['name']
      }
    end
    Side.import sides, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_factions(path)
    factions = JSON.parse(File.read(path))
    factions.map! do |f|
      {
        id: f['id'],
        description: f['description'],
        is_mini: f['is_mini'],
        name: f['name'],
        side_id: f['side_id']
      }
    end
    Faction.import factions, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_types(path)
    types = JSON.parse(File.read(path))
    types.map! do |t|
      {
        id: t['id'],
        name: t['name'],
        side_id: t['side_id']
      }
    end
    CardType.import types, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_subtypes(path)
    subtypes = JSON.parse(File.read(path))
    subtypes.map! do |st|
      {
        id: st['id'],
        name: st['name']
      }
    end
    CardSubtype.import subtypes, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def flatten_subtypes(all_subtypes, card_subtypes)
    return if card_subtypes.nil?

    subtype_names = []
    card_subtypes.each do |subtype|
      subtype_names << all_subtypes[subtype].name
    end
    subtype_names.join(' - ')
  end

  def import_cards(cards)
    subtypes = CardSubtype.all.index_by(&:id)

    new_cards = []
    cards.each do |card|
      new_card = RawCard.new(
        id: card['id'],
        card_type_id: card['card_type_id'],
        side_id: card['side_id'],
        faction_id: card['faction_id'],
        agenda_points: card['agenda_points'],
        base_link: card['base_link'],
        deck_limit: card['deck_limit'],
        influence_cost: card['influence_cost'],
        influence_limit: card['influence_limit'],
        memory_cost: card['memory_cost'],
        minimum_deck_size: card['minimum_deck_size'],
        narrative_text: card['narrative_text'],
        pronouns: card['pronouns'],
        pronunciation_approximation: card['pronunciation_approx'],
        pronunciation_ipa: card['pronunciation_ipa'],
        title: card['title'],
        stripped_title: card['stripped_title'],
        stripped_text: card['stripped_text'],
        text: card['text'],
        trash_cost: card['trash_cost'],
        is_unique: card['is_unique'],
        display_subtypes: flatten_subtypes(subtypes, card['subtypes']),
        attribution: card['attribution'],
        designed_by: card['designed_by'],
        layout_id: card.key?('layout_id') ? card['layout_id'] : 'normal'
      )
      if card.key?('cost')
        new_card.cost = (card['cost'].nil? ? -1 : card['cost'])
      end
      if card.key?('strength')
        new_card.strength = (card['strength'].nil? ? -1 : card['strength'])
      end

      if new_card.card_type_id == 'agenda'
        new_card.advancement_requirement = (card['advancement_requirement'].nil? ? -1 : card['advancement_requirement'])
      end

      # Look for specific abilities and attributes:
      if new_card.text
        m = new_card.text.match(/\+([X\d]+)\[link\]/)
        if m && m.captures.length == 1
          link_provided = m.captures[0]
          # Null is equivalent to "does not provide link" and we will use -1 to map to X.
          # TODO(plural): Ensure that any cards that match this condition end up with -1
          new_card.link_provided = link_provided == 'X' ? -1 : link_provided
        end
      end

      if new_card.text
        m = new_card.text.match(/\+([X\d]+)\[mu\]/)
        if m && m.captures.length == 1
          mu_provided = m.captures[0]
          # Null is equivalent to "does not provide mu" and we will use -1 to map to X.
          new_card.mu_provided = (mu_provided == 'X' ? -1 : mu_provided)
        end
      end

      if new_card.text
        m = new_card.text.match('([X\d]+)\[recurring-credit\]')
        if m && m.captures.length == 1
          num_recurring_credits = m.captures[0]
          # Null is equivalent to "does not provide recurring credits" and we will use -1 to map to X.
          new_card.recurring_credits_provided = num_recurring_credits == 'X' ? -1 : num_recurring_credits
        end
      end

      new_card.interrupt = true if new_card.text&.include?('[interrupt] →')

      # Geist and Tech trader are more trash *triggers* than abilities.
      new_card.trash_ability = true if new_card.text&.include?('[trash]')

      if new_card.text && new_card.card_type_id == 'ice' && new_card.text.include?('[subroutine]')
        # First look for gains subroutines text, record it and then remove it.
        # This only works with single gains "[subroutine]" instances, which is fine for now.
        t = new_card.text
        m = t.match(/gains "\[subroutine\].*?"/)
        gains_subroutines = false
        if m
          gains_subroutines = true
          t = t.gsub(/gains "\[subroutine\].*?"/, '')
        end
        num_printed_subroutines = t.scan(/\[subroutine\]/).length
        new_card.gains_subroutines = gains_subroutines
        new_card.num_printed_subroutines = num_printed_subroutines
      end

      if new_card.text&.include?(' can be advanced') && new_card.text.match("#{new_card.title} can be advanced")
        new_card.advanceable = true
      end

      # leaving this vague to catch things that have and impose additional costs.
      new_card.additional_cost = true if new_card.text&.include?('As an additional cost to')

      if new_card.text && (new_card.text.include?('When the Runner encounters this ice') || new_card.text.include?("When the Runner encounters #{new_card.title}}")) # rubocop:disable Layout/LineLength
        new_card.on_encounter_effect = true
      end

      if new_card.text && (new_card.text.include?('When you rez') || new_card.text.include?("#{new_card.title} when it is rezzed")) # rubocop:disable Layout/LineLength
        new_card.rez_effect = true
      end

      if new_card.text && (new_card.text.match?(/trace(\[\d+| X| \d+)/i) || new_card.text.match?('<trace>'))
        new_card.performs_trace = true
      end

      # TODO(plural): Add these in as well
      # - click_ability / click_cost
      # - [credit] - credit cost or paid ability?
      new_cards << new_card
    end

    puts "  About to save #{new_cards.length} cards..."
    num_cards = 0
    new_cards.each_slice(250) do |s|
      num_cards += s.length
      puts "  #{num_cards} cards"
      RawCard.import s, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
    end
  end

  def import_card_faces(cards)
    # Use a transaction since we are deleting the card_faces and card_faces_card_subtypes tables completely.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing card face -> card subtype mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM card_faces_card_subtypes')
        puts 'Hit an error while deleting card face -> card subtype mappings. rolling back.'
        raise ActiveRecord::Rollback
      end

      puts '  Clear out existing card faces'
      unless ActiveRecord::Base.connection.delete('DELETE FROM card_faces')
        puts 'Hit an error while deleting card faces. rolling back.'
        raise ActiveRecord::Rollback
      end

      subtypes = CardSubtype.all.index_by(&:id)

      cards.each do |card|
        # Only generate faces for cards with multiple faces
        next if !card.key?('layout_id') || card['layout_id'].nil? || card['layout_id'] == 'normal'

        # The first face of a card is just the main Card object and we do not make a CardFace for it.
        # The rest of the faces are generated from the explicitly-defined faces of the card.
        # Missing attributes are assumed to be unchanged.
        i = 0
        card['faces'].each do |face|
          face_subtypes = face.key?('subtypes') ? face['subtypes'] : []
          # There aren't enough cards with multiple faces to worry about optimizing inserts for them.
          new_face = CardFace.new(
            card_id: card['id'],
            face_index: i
          )
          new_face.base_link = face['base_link'] if face.key?('base_link')
          display_subtypes = []
          if face.key?('subtypes')
            face['subtypes'].each do |s|
              unless subtypes.key?(s)
                puts "subtype #{s} is invalid for card face for #{new_face.card_id}"
                raise ActiveRecord::Rollback
              end
              display_subtypes << subtypes[s].name
            end
          end
          new_face.display_subtypes = display_subtypes.join(' - ') if face.key?('subtypes')
          new_face.stripped_text = face['stripped_text'] if face.key?('stripped_text')
          new_face.stripped_title = face['stripped_title'] if face.key?('stripped_title')
          new_face.text = face['text'] if face.key?('text')
          new_face.title = face['title'] if face.key?('title')

          new_face.save

          next if face_subtypes.nil?

          face_subtypes.each do |s|
            puts "  Adding subtype #{s} to face #{i} of card #{new_face.card_id}"
            cfcs = CardFaceCardSubtype.new(
              card_id: new_face.card_id,
              face_index: i,
              card_subtype_id: s
            )
            cfcs.save
          end
          i += 1
        end
      end
    end
  end

  # This assumes that cards and card subtypes have already been loaded.
  def import_printing_subtypes
    printing_id_to_card_subtype_id = []
    RawCard.all.find_each do |c|
      c.printing_ids.each do |p|
        c.card_subtype_ids.each do |s|
          printing_id_to_card_subtype_id << [p, s]
        end
      end
    end

    # Use a transaction since we are completely replacing the mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing printing -> subtype mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM printings_card_subtypes')
        puts 'Hit an error while deleting card -> subtype mappings. rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      printing_id_to_card_subtype_id.each_slice(250) do |m|
        num_assoc += m.length
        puts "  #{num_assoc} printing -> subtype associations"
        sql = 'INSERT INTO printings_card_subtypes (printing_id, card_subtype_id) VALUES '
        vals = []
        m.each do |n|
          vals << "('#{n[0]}', '#{n[1]}')"
        end
        sql += vals.join(', ')
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card -> subtype mappings. rolling back.'
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  # We don't reload JSON files in here because we have already saved all the cards
  # with their subtypes fields and can parse from there.
  def import_card_subtypes(cards)
    card_id_to_subtype_id = Set.new
    cards.each do |c|
      next if c['subtypes'].nil?

      c['subtypes'].each do |st|
        card_id_to_subtype_id << [c['id'], st]
      end
    end
    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing card -> subtype mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM cards_card_subtypes')
        puts 'Hit an error while deleting card -> subtype mappings. rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      card_id_to_subtype_id.each_slice(250) do |m|
        num_assoc += m.length
        puts "  #{num_assoc} card -> subtype associations"
        sql = 'INSERT INTO cards_card_subtypes (card_id, card_subtype_id) VALUES '
        vals = []
        m.each do |n|
          vals << "('#{n[0]}', '#{n[1]}')"
        end
        sql += vals.join(', ')
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card -> subtype mappings. rolling back.'
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  def import_cycles(path)
    cycles = JSON.parse(File.read(path))
    cycles.map! do |c|
      {
        id: c['id'],
        name: c['name'],
        legacy_code: c['legacy_code'],
        position: c['position'],
        released_by: c['released_by']
      }
    end
    CardCycle.import cycles, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_set_types(path)
    set_types = JSON.parse(File.read(path))
    set_types.map! do |t|
      {
        id: t['id'],
        name: t['name'],
        description: t['description']
      }
    end
    CardSetType.import set_types, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def update_date_release_for_cycles
    CardCycle.all.find_each do |c|
      num_non_booster_sets = c.card_sets.where.not(card_set_type_id: 'booster_pack').count

      c.date_release = if num_non_booster_sets.positive?
                         c.card_sets.where.not(card_set_type_id: 'booster_pack').minimum(:date_release)
                       else
                         c.card_sets.minimum(:date_release)
                       end
      c.save
    end
  end

  def import_sets(path)
    printings = JSON.parse(File.read(path))
    printings.map! do |s|
      {
        "id": s['id'],
        "name": s['name'],
        "date_release": s['date_release'],
        "size": s['size'],
        "card_cycle_id": s['card_cycle_id'],
        "card_set_type_id": s['card_set_type_id'],
        "position": s['position'],
        "legacy_code": s['legacy_code'],
        "released_by": s['released_by']
      }
    end
    CardSet.import printings, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_printings(printings)
    card_sets = CardSet.all.index_by(&:id)

    new_printings = []
    printings.each do |printing|
      new_printings << RawPrinting.new(
        id: printing['id'],
        flavor: printing['flavor'],
        display_illustrators: printing['illustrator'],
        position: printing['position'],
        quantity: printing['quantity'],
        card_id: printing['card_id'],
        card_set_id: printing['card_set_id'],
        date_release: card_sets[printing['card_set_id']].date_release,
        released_by: printing['released_by']
      )
    end

    num_printings = 0
    new_printings.each_slice(250) do |s|
      num_printings += s.length
      puts "  #{num_printings} printings"
      RawPrinting.import s, on_duplicate_key_update: { conflict_target: [:id], columns: :all }, raise_error: true
    end

    # Use ROW_NUMBER() to identify the position of each printing in the each set.
    sql = <<~SQL
      UPDATE
        printings
      SET
        position_in_set = sp.pos
      FROM (
        SELECT
          id as printing_id,
          ROW_NUMBER() OVER(PARTITION BY card_set_id ORDER BY position) as pos
        FROM
          printings
        ) AS sp
      WHERE
        printings.id = sp.printing_id
    SQL
    ActiveRecord::Base.connection.execute(sql)
  end

  def import_illustrators
    # Use a transaction since we are deleting the illustrator and mapping tables.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing illustrator -> printing mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM illustrators_printings')
        puts 'Hit an error while deleting illustrator -> printing mappings. rolling back.'
        raise ActiveRecord::Rollback
      end

      puts '  Clear out existing illustrators'
      unless ActiveRecord::Base.connection.delete('DELETE FROM illustrators')
        puts 'Hit an error while deleting illustrators. rolling back.'
        raise ActiveRecord::Rollback
      end

      illustrators = Set[]
      illustrators_to_printings = []
      illustrator_num_printings = {}
      num_its = 0
      printings = RawPrinting.all
      printings.each do |printing|
        next unless printing.display_illustrators

        printing.display_illustrators.split(/\s*[,&]\s*/).each do |i|
          illustrators.add(i)
          num_its += 1
          illustrators_to_printings << {
            "illustrator_id": text_to_id(i),
            "printing_id": printing.id
          }
          illustrator_num_printings[i] = 0 unless illustrator_num_printings.key?(i)
          illustrator_num_printings[i] += 1
        end
      end

      ill = []
      illustrators.each do |i|
        ill << {
          "id": text_to_id(i),
          "name": i,
          "num_printings": illustrator_num_printings[i]
        }
      end

      Illustrator.import ill, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
      IllustratorPrinting.import illustrators_to_printings,
                                 on_duplicate_key_update: { conflict_target: %i[illustrator_id printing_id],
                                                            columns: :all }
    end
  end

  def import_printing_faces(printings)
    # Use a transaction since we are deleting the card_faces and card_faces_card_subtypes tables completely.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing printing faces'
      unless ActiveRecord::Base.connection.delete('DELETE FROM printing_faces')
        puts 'Hit an error while deleting printing faces. rolling back.'
        raise ActiveRecord::Rollback
      end

      printings.each do |printing|
        # Only generate faces for cards with multiple faces
        next if !printing.key?('faces') || printing['faces'].empty?

        # The first face of a printing is just the main Printing object and we do not make a PrintingFace for it.
        # The rest of the faces are generated from the explicitly-defined faces of the printing.
        # Missing attributes are assumed to be unchanged.
        i = 0
        printing['faces'].each do |face|
          # There aren't enough cards with multiple faces to worry about optimizing inserts for them.
          new_face = PrintingFace.new(
            printing_id: printing['id'],
            face_index: i
          )
          new_face.copy_quantity = face['copy_quantity'] if face.key?('copy_quantity')
          new_face.flavor = face['flavor'] if face.key?('flavor')

          new_face.save
          i += 1
        end
      end
    end
  end

  def import_formats(formats_json)
    formats = []
    formats_json.each do |f|
      active_id = nil
      f['snapshots'].each do |s|
        next unless s['active']

        active_id = s['id']
      end
      formats << Format.new(
        id: f['id'],
        name: f['name'],
        active_snapshot_id: active_id
      )
    end
    Format.import formats, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_card_pools(card_pools)
    new_card_pools = []
    card_pools.each do |p|
      new_card_pools << CardPool.new(
        id: p['id'],
        name: p['name'],
        format_id: p['format_id']
      )
    end
    CardPool.import new_card_pools, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_card_pool_card_cycles(card_pools)
    card_pool_id_to_cycle_id = Set.new

    # Collect each card pool's cycles
    card_pools.each do |p|
      next if p['card_cycle_ids'].nil?

      p['card_cycle_ids'].each do |s|
        card_pool_id_to_cycle_id << [p['id'], s]
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing card_pool -> cycle mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM card_pools_card_cycles')
        puts 'Hit an error while deleting card_pool -> cycle mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      card_pool_id_to_cycle_id.each_slice(250) do |m|
        num_assoc += m.length
        puts "  #{num_assoc} card_pool -> cycle associations"
        sql = 'INSERT INTO card_pools_card_cycles (card_pool_id, card_cycle_id) VALUES '
        vals = []
        m.each do |n|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('#{n[0]}', '#{n[1]}')"
        end
        sql += vals.join(', ')
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card_pool -> cycle mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  def import_card_pool_card_sets(card_pools)
    card_pool_id_to_set_id = Set.new

    # Get implied sets from cycles in the card_pool
    sql = <<~SQL
      SELECT
        card_pool_id,
        id
      FROM
        card_pools_card_cycles r
        INNER JOIN card_sets AS s
          ON r.card_cycle_id = s.card_cycle_id
    SQL
    ActiveRecord::Base.connection.execute(sql).each do |s|
      card_pool_id_to_set_id << [s['card_pool_id'], s['id']]
    end

    # Collect each card pool's sets
    card_pools.each do |p|
      next if p['card_set_ids'].nil?

      p['card_set_ids'].each do |s|
        card_pool_id_to_set_id << [p['id'], s]
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing card_pool -> card cycle mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM card_pools_card_sets')
        puts 'Hit an error while deleting card_pool -> card set mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      card_pool_id_to_set_id.each_slice(250) do |m|
        num_assoc += m.length
        puts "  #{num_assoc} card_pool -> card set associations"
        sql = 'INSERT INTO card_pools_card_sets (card_pool_id, card_set_id) VALUES '
        vals = []
        m.each do |n|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('#{n[0]}', '#{n[1]}')"
        end
        sql += vals.join(', ')
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card_pool -> card set mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  def import_card_pool_cards(card_pools)
    card_pool_id_to_card_id = Set.new

    # Get implied cards from sets in the card_pool
    sql = <<~SQL
      SELECT
        card_pool_id,
        card_id
      FROM
        card_pools_card_sets AS r
        INNER JOIN printings AS p
          ON r.card_set_id = p.card_set_id
        GROUP BY 1,2
    SQL
    ActiveRecord::Base.connection.execute(sql).each do |s|
      card_pool_id_to_card_id << [s['card_pool_id'], s['card_id']]
    end

    # Collect each card pool's cards
    card_pools.each do |p|
      next if p['cards'].nil?

      p['cards'].each do |s|
        card_pool_id_to_card_id << [p['id'], s]
      end
    end

    # Use a transaction since we are deleting the mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing card_pool -> card mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM card_pools_cards')
        puts 'Hit an error while deleting card_pool -> card mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end

      num_assoc = 0
      card_pool_id_to_card_id.each_slice(1000) do |m|
        num_assoc += m.length
        puts "  #{num_assoc} card_pool -> card associations"
        sql = 'INSERT INTO card_pools_cards (card_pool_id, card_id) VALUES '
        vals = []
        m.each do |n|
          # TODO(ams): use the associations object for this or ensure this is safe
          vals << "('#{n[0]}', '#{n[1]}')"
        end
        sql += vals.join(', ')
        unless ActiveRecord::Base.connection.execute(sql)
          puts 'Hit an error while inserting card_pool -> card mappings. Rolling back.'
          raise ActiveRecord::Rollback
        end
      end
    end
  end

  def import_restrictions(restrictions)
    new_restrictions = []
    restrictions.each do |m|
      new_restrictions << Restriction.new(
        id: m['id'],
        name: m['name'],
        date_start: m['date_start'],
        point_limit: m['point_limit'],
        format_id: m['format_id']
      )
    end
    Restriction.import new_restrictions, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def import_restriction_cards(restrictions)
    banned = []
    restricted = []
    universal_faction_cost = []
    global_penalty = []
    points = []
    restrictions.each do |r|
      # Banned cards
      r['banned']&.each do |card|
        banned << RestrictionCardBanned.new(
          restriction_id: r['id'],
          card_id: card
        )
      end
      # Restricted cards
      r['restricted']&.each do |card|
        restricted << RestrictionCardRestricted.new(
          restriction_id: r['id'],
          card_id: card
        )
      end
      # Cards with a universal faction cost
      r['universal_faction_cost']&.each do |cost, cards|
        cards.each do |card|
          universal_faction_cost << RestrictionCardUniversalFactionCost.new(
            restriction_id: r['id'],
            card_id: card,
            value: cost
          )
        end
      end
      # Cards with a global influence penalty
      r['global_penalty']&.each_value do |cards|
        cards.each do |card|
          global_penalty << RestrictionCardGlobalPenalty.new(
            restriction_id: r['id'],
            card_id: card
          )
        end
      end
      # Cards with a points cost
      next if r['points'].nil?

      r['points'].each do |cost, cards|
        cards.each do |card|
          points << RestrictionCardPoints.new(
            restriction_id: r['id'],
            card_id: card,
            value: cost
          )
        end
      end
    end

    # Use a transaction since we are deleting all the restriction mapping tables.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing restriction -> card mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_cards_banned')
        puts 'Hit an error while deleting banned cards mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_cards_restricted')
        puts 'Hit an error while deleting restricted cards mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_cards_universal_faction_cost')
        puts 'Hit an error while deleting universal faction cost cards mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_cards_global_penalty')
        puts 'Hit an error while deleting global penalty cards mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_cards_points')
        puts 'Hit an error while deleting points cards mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      RestrictionCardBanned.import banned
      RestrictionCardRestricted.import restricted
      RestrictionCardUniversalFactionCost.import universal_faction_cost
      RestrictionCardGlobalPenalty.import global_penalty
      RestrictionCardPoints.import points
    end
  end

  def import_restriction_subtypes(restrictions)
    banned = []
    restrictions.each do |r|
      subtypes = r['subtypes']
      next if subtypes.nil?

      # Banned subtypes
      next if subtypes['banned'].nil?

      subtypes['banned'].each do |subtype|
        banned << RestrictionCardSubtypeBanned.new(
          restriction_id: r['id'],
          card_subtype_id: subtype
        )
      end
    end

    # Use a transaction since we are deleting the restriction mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing restriction -> subtype mappings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM restrictions_card_subtypes_banned')
        puts 'Hit an error while deleting banned subtypes mappings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      RestrictionCardSubtypeBanned.import banned
    end
  end

  def import_snapshots(formats)
    snapshots = []
    formats.each do |f|
      f['snapshots'].each do |s|
        snapshots << Snapshot.new(
          id: s['id'],
          format_id: f['id'],
          card_pool_id: s['card_pool_id'],
          date_start: s['date_start'],
          restriction_id: s['restriction_id'],
          active: s['active'].nil? ? false : s['active']
        )
      end
    end
    Snapshot.import snapshots, on_duplicate_key_update: { conflict_target: [:id], columns: :all }
  end

  def strip_if_not_nil(str)
    return str if str.nil?

    str.strip
  end

  def import_rulings(rulings_json)
    rulings = []
    rulings_json.each do |r|
      rulings << Ruling.new(
        card_id: r['card_id'],
        question: strip_if_not_nil(r['question']),
        answer: strip_if_not_nil(r['answer']),
        text_ruling: strip_if_not_nil(r['text_ruling']),
        updated_at: r['date_update'],
        nsg_rules_team_verified: r['nsg_rules_team_verified']
      )
    end

    # Use a transaction since we are deleting the restriction mapping table.
    ActiveRecord::Base.transaction do
      puts '  Clear out existing rulings'
      unless ActiveRecord::Base.connection.delete('DELETE FROM rulings')
        puts 'Hit an error while deleting rulings. Rolling back.'
        raise ActiveRecord::Rollback
      end
      Ruling.import rulings
    end
  end

  task :import, [:json_dir] => [:environment] do |_t, args|
    args.with_defaults(json_dir: '/netrunner-cards-json/v2/')

    puts 'Import card data...'

    # Preload directories that are used multiple times
    cards_json = load_multiple_json_files("#{args[:json_dir]}/cards/*.json")
    printings_json = load_multiple_json_files("#{args[:json_dir]}/printings/*.json")
    card_pools_json = load_multiple_json_files("#{args[:json_dir]}/card_pools/*.json")
    formats_json = load_multiple_json_files("#{args[:json_dir]}/formats/*.json")
    restrictions_json = load_multiple_json_files("#{args[:json_dir]}/restrictions/*/*.json")

    puts 'Importing Sides...'
    import_sides("#{args[:json_dir]}/sides.json")

    puts 'Import Factions...'
    import_factions("#{args[:json_dir]}/factions.json")

    puts 'Importing Cycles...'
    import_cycles("#{args[:json_dir]}/card_cycles.json")

    puts 'Importing Card Set Types...'
    import_set_types("#{args[:json_dir]}/card_set_types.json")

    puts 'Importing Sets...'
    import_sets("#{args[:json_dir]}/card_sets.json")

    puts 'Updating date_release for Cycles'
    update_date_release_for_cycles

    puts 'Importing Types...'
    import_types("#{args[:json_dir]}/card_types.json")

    puts 'Importing Subtypes...'
    import_subtypes("#{args[:json_dir]}/card_subtypes.json")

    puts 'Importing Cards...'
    import_cards(cards_json)

    puts 'Importing Subtypes for Cards...'
    import_card_subtypes(cards_json)

    puts 'Importing Card Faces...'
    import_card_faces(cards_json)

    puts 'Importing Printings...'
    import_printings(printings_json)

    puts 'Importing Printing Faces...'
    import_printing_faces(printings_json)

    puts 'Importing Subtypes for Printings...'
    import_printing_subtypes

    puts 'Importing Illustrators...'
    import_illustrators

    puts 'Importing Formats...'
    import_formats(formats_json)

    puts 'Importing Card Pools...'
    import_card_pools(card_pools_json)

    puts 'Importing Card-Pool-to-Cycle relations...'
    import_card_pool_card_cycles(card_pools_json)

    puts 'Importing Card-Pool-to-Set relations...'
    import_card_pool_card_sets(card_pools_json)

    puts 'Importing Card-Pool-to-Card relations...'
    import_card_pool_cards(card_pools_json)

    puts 'Importing Restrictions...'
    import_restrictions(restrictions_json)

    puts 'Importing Restriction Cards...'
    import_restriction_cards(restrictions_json)

    puts 'Importing Restriction Subtypes...'
    import_restriction_subtypes(restrictions_json)

    puts 'Importing Format Snapshots...'
    import_snapshots(formats_json)

    puts 'Importing Rulings...'
    rulings_json = load_multiple_json_files("#{args[:json_dir]}/rulings/*.json")
    import_rulings(rulings_json)

    puts 'Refreshing materialized view for restrictions...'
    Scenic.database.refresh_materialized_view(:unified_restrictions, concurrently: false, cascade: false)

    puts 'Refreshing materialized view for cards...'
    Scenic.database.refresh_materialized_view(:unified_cards, concurrently: false, cascade: false)

    puts 'Refreshing materialized view for printings...'
    Scenic.database.refresh_materialized_view(:unified_printings, concurrently: false, cascade: false)

    puts "unified_cards has #{Card.all.size} records."
    puts "unified_printings has #{Printing.all.size} records."
    puts "unified_restrictions has #{UnifiedRestriction.all.size} records."
    puts ''
    puts 'Done!'
  end
end
