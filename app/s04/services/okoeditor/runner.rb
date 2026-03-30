# frozen_string_literal: true

module Services
  module Okoeditor
    class Runner
      TASK_NAME = 'okoeditor'

      # All pages share the same ID for the Skolwin-related record
      SKOLWIN_ID = '380792b2c86d9c5be670b3bde48e187b'

      def initialize(hub_client:, logger: $stdout)
        @hub_client = hub_client
        @logger     = logger
      end

      def call
        log('=== OKO Editor Agent Starting ===')

        # ── 1. Reclassify the Skolwin incident as animal sighting ─────────────
        log('Step 1: Reclassifying Skolwin incident to animal sighting...')
        r1 = api_update(
          page: 'incydenty',
          id: SKOLWIN_ID,
          title: 'MOVE04 Aktywność zwierząt nieopodal miasta Skolwin',
          content: 'Czujniki zarejestrowały ruch w okolicach miasta Skolwin. ' \
                   'Po analizie nagrań potwierdzono, że sygnał pochodził od grupy zwierząt ' \
                   '(prawdopodobnie bobrów) przemieszczających się w kierunku rzeki. ' \
                   'Ruch był nieregularny, co jest typowe dla dzikich zwierząt szukających pożywienia. ' \
                   'Brak oznak obecności ludzi lub pojazdów.'
        )
        log("  → #{r1.inspect}")

        # ── 2. Mark Skolwin task as done, mention animals ─────────────────────
        log('Step 2: Marking Skolwin task as done...')
        r2 = api_update(
          page: 'zadania',
          id: SKOLWIN_ID,
          done: 'YES',
          content: 'Zbadano nagrania z okolic Skolwina. Potwierdzono, że zarejestrowany ruch ' \
                   'pochodził od zwierząt — widziano bobry w pobliżu rzeki. ' \
                   'Brak śladów obecności ludzi ani pojazdów. Zamykam zadanie.'
        )
        log("  → #{r2.inspect}")

        # ── 3. Redirect attention: add human movement report near Komarowo ────
        # Re-purpose an existing non-critical incident to report on Komarowo
        log('Step 3: Creating incident about human movement near Komarowo...')
        komarowo_id = find_komarowo_target
        r3 = api_update(
          page: 'incydenty',
          id: komarowo_id,
          title: 'MOVE01 Wykrycie ruchu ludzi w okolicach miasta Komarowo',
          content: 'Czujniki wykryły obecność ludzi poruszających się w okolicach niezamieszkałego miasta Komarowo. ' \
                   'Zaobserwowano kilka postaci przemieszczających się w pobliżu opuszczonych budynków. ' \
                   'Ruch sugeruje zorganizowaną aktywność. Zaleca się wysłanie patrolu rozpoznawczego ' \
                   'w celu weryfikacji tożsamości i celu obecności tych osób.'
        )
        log("  → #{r3.inspect}")

        # ── 4. Run done to verify ────────────────────────────────────────────
        log('Step 4: Running done action...')
        verification = api_done
        log("Verification: #{verification.inspect}")

        flag = verification['message'] || verification.to_s
        log("Flag: #{flag}")

        { verification: verification, flag: flag }
      end

      private

      def find_komarowo_target
        # Use a non-critical incident that can be repurposed
        # Pick one of the radio-related ones that isn't about Skolwin or Domatowo
        '351c0d9c90d66b4c040fff1259dd191d'
      end

      def api_call(answer)
        resp = @hub_client.verify_raw(task: TASK_NAME, answer: answer)
        JSON.parse(resp.body)
      end

      def api_update(page:, id:, **fields)
        api_call({ action: 'update', page: page, id: id }.merge(fields))
      end

      def api_done
        api_call({ action: 'done' })
      end

      def log(msg)
        @logger.puts("[okoeditor] #{msg}")
      end
    end
  end
end
