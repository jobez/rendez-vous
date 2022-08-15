(ns rv
  (:require
   [reagent.core :as r]
   [reagent.dom :as rdom]
   [react :as react]
   [goog.crypt :as crypt]
   [goog.crypt.Pkcs7]
   [goog.crypt.Md5]
   [clojure.string :as str]
   [shadow.resource :as rc]
   ["./helpers" :as helpers]
   ["bignumber.js" :as bn]
   ["starknet/provider" :refer [Provider]]
   ["starknet/utils/number" :refer [toBN toHex toFelt]]
   ["starknet/utils/hash" :refer [pedersen  computeHashOnElements]]
   ["starknet/utils/shortString" :refer [encodeShortString decodeShortString]]
   ["@starknet-react/core" :refer
    [StarknetProvider
     getInstalledInjectedConnectors
     useConnectors
     useContract
     useStarknetInvoke
     useStarknetCall
     useStarknet]]
   [clojure.walk :as walk])

  (:import [goog.crypt Sha256 Hmac Aes Cbc Md5]))



;; * helpers

(goog-define hf-token "")
(goog-define rv-addr "0x23f15b473e03015c0ae1f597ab1c417ee3b8337a64c40349b761474e11375c1")

(defn edn-to-json-str
  "Convert EDN to JSON str"
  [edn]
  (->> edn
       (clj->js)
       (js/JSON.stringify)))

(defn json-str-to-edn
  "Convert a JSON str to EDN"
  [json-str]
  (->> json-str
       (js/JSON.parse)
       (js->clj)
       (walk/keywordize-keys)))

(defn set-local-item!
  "Set `key' in browser's localStorage to `val`."
  [key val]
  (let [json-val (edn-to-json-str val)]
    (.setItem (.-localStorage js/window) key json-val)))

(defn get-local-item
  "Returns value of `key' from browser's localStorage."
  [key]
  (let [json-val (.getItem (.-localStorage js/window) key)]
    (json-str-to-edn json-val)))

(defn remove-local-item!
  "Remove the browser's localStorage value for the given `key`"
  [key]
  (.removeItem (.-localStorage js/window) key))

(defonce salt 50)

(defn ensure-sixteen-length [string]
  (let [difference (- (.-length string) 16)]
    (case (js/Math.sign difference)
      -1 (apply str string (repeat (abs difference) "0"))
      1 (subs string 0 16)
      0 str)))

(defn jncrypt
  "Encrypts with AES/CBC/PKCS{5/7}Padding by hashing a 256 bit key out
  of key. Key can be any Clojure value, but should provide enough
  secret entropy!
  You can provide an alternate initial vector of unsigned(!) bytes of size 16 for CBC."
  [key m & {:keys [iv] :or {iv  [6 224 71 170 241 204 115 21 30 8 46 223 106 207 55 42]}}]
  (let [decode goog.crypt/stringToByteArray
        cipher (goog.crypt.Aes. (decode key))
        cbc (goog.crypt.Cbc. cipher)
        pkcs7 (goog.crypt.Pkcs7.)
        padded (.encode pkcs7 16 m)]
    (.encrypt cbc padded (clj->js iv))))

(defn decrypt
  "Decrypts with AES/CBC/PKCS{5/7}Padding by hashing a 256 bit key out of key.
  You can provide an alternate initial vector of unsigned(!) bytes of size 16 for CBC."
  [key e & {:keys [iv] :or {iv  [6 224 71 170 241 204 115 21 30 8 46 223 106 207 55 42]}}]
  (let [decode goog.crypt/stringToByteArray
        cipher (goog.crypt.Aes. (decode key))
        cbc (goog.crypt.Cbc. cipher)
        pkcs7 (goog.crypt.Pkcs7.)]
    (.decode pkcs7 16 (.decrypt cbc e (clj->js iv)))))

(defn encoded-string->p-hash [encoded-string]
  (->> encoded-string
       (reduce (fn [acc el]
                 
                 (pedersen #js [acc el]
                           ))
               )))

(defn encoded-string->p-hash-salted [salt encoded-string]
  (->> encoded-string
       (reduce (fn [acc el]
                 
                 (pedersen #js [acc el]
                           ))
               salt)))

(defn text->encoded-short-str-arr [text]
  (->> text
       (re-seq #".{1,31}" )
       (map encodeShortString)))

(defn text->p-hash [text]
  (->> text
       text->encoded-short-str-arr
       encoded-string->p-hash))

(defn text->p-hash-salted [text salt]
  (->> text
       text->encoded-short-str-arr
       (encoded-string->p-hash-salted salt)))

(defn maybe-deprefix [supposed-hex]
  (if (clojure.string/starts-with? "0x" supposed-hex)
    (clojure.string/replace-first supposed-hex
                                  #"0x"
                                  "")
    supposed-hex))

(defn encoded-short-str->str [%string]
  (let [string (maybe-deprefix %string)
        by-two (re-seq #".{2}" string)]
    (reduce #(->> (js/parseInt %2 16)
                  (js/String.fromCharCode )
                  (str %1 ))
            ""
          by-two)
    ))


;; * other stuff
(declare use-cipher str->encoded-short-str init jhnn-provider)

;; prompt hash 0x57696c6c207468697320776f726b206e6f773f

(defonce rv-abi (rc/inline "abis/response.json"))

(defn use-rv []
  (useContract #js {:abi (aget (js/JSON.parse rv-abi) "abi") 
                    :address rv-addr}))

(defn mutate! []
  (set! js/window.starknet.provider jhnn-provider)
  (set! js/window.starknet.account.baseUrl jhnn-provider.baseUrl)
  (set! js/window.starknet.account.feederGatewayUrl jhnn-provider.feederGatewayUrl)
  (set! js/window.starknet.account.gatewayUrl jhnn-provider.gatewayUrl)
  (println "mutated!"))

(defn connect []
  (let [connectors-js (->> (useConnectors)
                           )
        connect (aget connectors-js "connect")
        connectors (aget connectors-js "connectors")]

    (println "connectors" connectors-js)
    [:<>
     (for [connector connectors]
       [:button
        {:key (.id connector)
         :on-click (fn []
                     (connect connector)
                     (js/setTimeout mutate! 2000)
                     )}
        (str "Connect " (.name connector))])]))


;; (defn use-submit-prompt [rv-contract-js]
;;   let [contract (some-> rv-contract-js
;;                          (aget "contract"))
;;        contract-call-cypher-js (useStarknetCall #js {:contract contract
;;                                                       :method ""
;;                                                      :args #js []} )])

(defn prompt-contract []
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        [text set-text] (react/useState "")
        
        account (some-> starknet-js
                        (aget "account")
                        )
        invoke-submit-prompt (useStarknetInvoke #js {:contract contract :method
                                                     "submit_prompt"})
        [reset error submit-prompt! data loading]
        (mapv #(some->  invoke-submit-prompt
                       (aget %1))
              ["reset" "error" "invoke" "data" "loading"])

        ]
    
    (when account
      (if (or data error)
        [:div
         [:b (or data error)]
         [:button {:on-click #((reset))} "reset"]]
        (if loading
          [:i loading]
          [:div
           [:textarea {:name "texty"
                       :value text
                       :on-change    #(set-text (.. % -target -value))
                       :on-key-press (fn [e]
                                       (when (= (.-charCode e) 13)
                                         (.preventDefault e)
                                         (set-text "")))
                       :cols "40"
                       :rows "5"}]
           [:button {:on-click (fn [e]
                                 (let [partitioned-strings (re-seq #".{1,31}" text)
                                       prompt-as-encoded-strings (->> partitioned-strings
                                                                      (map encodeShortString)
                                                            )
                                       prompt-h (encoded-string->p-hash prompt-as-encoded-strings)]
                                   (-> (submit-prompt! #js {:args #js [prompt-h (toFelt 2)
                                                                       (toFelt 3) (clj->js
                                                                                prompt-as-encoded-strings) 
                                                              ]})
                                       )
                                   (set-local-item! (str "prompt/" (text->p-hash text))
                                                    {:content text}))
                                 )}
            (str "submit-prompt!" data)]])))))





(def bigint->string (comp decodeShortString toHex))

(defn text-submitter [text on-text-change on-submit submit-action-presentation]
  [:div
   [:textarea {:name "texty"
               :value text
               :on-change    on-text-change
               :cols "40"
               :rows "5"}]
   [:button {:on-click on-submit}
    submit-action-presentation]])

(defn make-rv-view [selected-prompt entered-response]
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        invoke-arrange-rv (useStarknetInvoke #js {:contract contract
                                                  :method
                                                  "arrange_rendez_vous"})
        [reset error invoke-arrange-rv! data loading]
        (mapv #(some->  invoke-arrange-rv
                        (aget %1))
              ["reset" "error" "invoke" "data" "loading"])]
    [:div
     [:div error]
     [:button {:on-click
               (fn [_]
                (let [
                      prompt-h (text->p-hash selected-prompt)

                      response-h (text->p-hash-salted entered-response salt)]
                  
                  (invoke-arrange-rv! #js {:args #js [prompt-h
                                                      response-h
                                                      ]})))}
      (str "arrange rv " )]
     ]))



(defn sign-for-disclosure [key message]
  (jncrypt
   (->> key ensure-sixteen-length)
   (goog.crypt/stringToByteArray message)))

(defn disclose-view [prompt-h response-h match-h text encoded-short-str-response signing-key]
  (let [
        signed-message (sign-for-disclosure signing-key text)
        signed-message-h (encoded-string->p-hash signed-message)
        contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        invoke-disclose-response (useStarknetInvoke #js {:contract contract :method
                                                   "submit_response_for_match"
                                                         })
        [reset error disclose-response! data loading]
        (mapv #(some-> invoke-disclose-response
                       (aget %1))
              ["reset" "error" "invoke" "data" "loading"])
        call-get-rv (useStarknetCall #js {:contract contract :method
                                          "get_rendez_vous"
                                          :args #js [prompt-h, salt,
                                                     response-h, encoded-short-str-response,
                                                     match-h]})

        [rv-res error1
         loading1 reset1]
        (mapv #(some->  call-get-rv
                        (aget %1))
              ["data" "error" "loading" "reset"])]
    (println match-h response-h)
    (react/useEffect
     (fn []
              
       (when-let [{:keys [response-h]} (get-local-item (str "prompt/"  prompt-h))]
         (when response-h
           (let [response (get-local-item (str "response/" response-h))
                 ]
             (when rv-res
              (set-local-item! (str "response/" response-h) (assoc response :match (goog.crypt/byteArrayToString (decrypt (ensure-sixteen-length (toHex (aget rv-res "0"))) (aget rv-res "1")))))))))
       (fn []))
     #js [rv-res])
    (js/console.warn error1)

    (def rv-res rv-res)
    [:div
     [:div (some->> 
            rv-res
            js->clj
            cljs.pprint/pprint
            with-out-str)]
     (when-not rv-res
      [:button
       {:on-click (fn [e]
                    (let [response (get-local-item (str "response/" response-h))
                          prompt    (get-local-item (str "prompt/" prompt-h))
                          updated-prompt (assoc prompt :response-h response-h)
                          updated-response (assoc response :disclosed true)]
                      (disclose-response! #js {:args #js [prompt-h, response-h, match-h, signed-message-h signed-message ]})
                      (set-local-item! (str "response/" response-h)
                                     updated-response))
                    
                    )}
       "disclose yours"])
     [:div
      (when rv-res
        (goog.crypt/byteArrayToString (decrypt (ensure-sixteen-length (toHex (aget rv-res "0"))) (aget rv-res "1"))))]]
))

(defn their-hash [a-hash b-hash our-hash]
  (if (= a-hash our-hash )
    b-hash
    a-hash))

(defn match-view [match salted-response-hash
                  prompt-h
                  text
                  encoded-short-str-response]
  (let [{:strs [a_match_hash b_match_hash similarity] :as match} match
        contract-js (use-rv)
        match_hash (their-hash a_match_hash b_match_hash salted-response-hash )
        contract (some-> contract-js
                         (aget "contract"))
        call-get-rv-detail (useStarknetCall #js {:contract contract :method
                                                   "get_rendez_vous_detail"
                                                 :args #js [prompt-h, salt, salted-response-hash, encoded-short-str-response, (toHex match_hash)]})
        [rv-detail error
         loading reset]
        (mapv #(some->  call-get-rv-detail
                        (aget %1))
              ["data" "error" "loading" "reset"])
        signing-hash (some->> rv-detail
               js->clj
               first
               toHex
               )]
    (js/console.error error)
   [:div
    [:div ("Match hash " (toHex match_hash))]
    [:div (str "similiarity" (.toString (helpers/from64x61 similarity)))]
    ;; [:div signing-hash]
    (when signing-hash
      [:f> disclose-view prompt-h salted-response-hash (toHex match_hash) text encoded-short-str-response signing-hash])]))

(defn matches-view [matches
                    salted-response-hash
                    prompt-h
                    text
                    encoded-short-str-response]
  [:div
   [:div
    (doall
     (for [{:strs [a_match_hash b_match_hash similarity] :as match} matches]
       [:div
        {:key (toHex b_match_hash)}
        [:f> match-view match
         salted-response-hash
         prompt-h
         text
         encoded-short-str-response]]))]
   (->>
    matches
    js->clj
    cljs.pprint/pprint
    with-out-str)])

(defn inner-matches-for-response-view [selected-prompt text]
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        salted-response-hash (text->p-hash-salted text salt)
        prompt-h (text->p-hash selected-prompt)
        encoded-short-str-response
        (->> text
             text->encoded-short-str-arr
             clj->js)
        call-get-matches (useStarknetCall #js {:contract contract :method
                                                   "check_matches_for_response_h"
                                              :args #js [prompt-h, salt, salted-response-hash, encoded-short-str-response]})

                
        [matches error loading reset]
        (mapv #(some->  call-get-matches
                       (aget %1))
              ["data" "error" "loading" "reset"])
        matches (if (zero? (-> matches js->clj first))
                  nil
                  matches)]

    [:div
     [:div (or error loading)]
     [:div
      (if (or loading (not matches))
        [:div "its loading btw"]
        [:f> matches-view
         (-> matches js->clj first)
         salted-response-hash
         prompt-h
         text
         encoded-short-str-response])
      ]])
  )

(defn matches-for-response-view [selected-prompt selected-response]
  (let [[display-inner set-display-inner] (react/useState false)]
    [:div
     [:button {:on-click (fn [_]
                           (let [
                                 prompt-h (text->p-hash selected-prompt)

                                 response-h (text->p-hash-salted selected-response salt)]
                             (println selected-prompt "<- selected prompt" prompt-h response-h)
                             ;; (invoke-arrange-rv! #js {:args #js [prompt-h
                             ;;                                     response-h
                             ;;                                     ]})
                             (set-display-inner true))
                           
                           )}
      (str "check for matches")]
     
     (when display-inner
       [:f> inner-matches-for-response-view selected-prompt selected-response])]))

(defn response-view [selected-prompt]
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        [text set-text] (react/useState "")
        [hugging-error set-hugging-error] (react/useState "")
        account (some-> starknet-js
                        (aget "account")
                        )
        invoke-submit-response (useStarknetInvoke #js {:contract contract :method
                                                       "submit_response"})
        [reset error submit-response! data loading]
        (mapv #(some->  invoke-submit-response
                        (aget %1))
              ["reset" "error" "invoke" "data" "loading"])]

    (react/useEffect
     (fn []
              
       (when-let [{:keys [response-h]} (get-local-item (str "prompt/" (text->p-hash selected-prompt)))]
         (when response-h
           (let [response (get-local-item (str "response/" response-h))
                 ]
             (set-text (:content response)))))
       (fn []
         ))
     #js [])
    [:div
     [:div (if (not (empty? hugging-error ))
             hugging-error
             error)]
     [text-submitter
      text
      #(set-text (.. % -target -value))
      (fn get-embed-and-transact [_]
       
        (def hf-endpoint "https://api-inference.huggingface.co/pipeline/feature-extraction/sentence-transformers/all-mpnet-base-v2")
        (let [retries (volatile! 0)]
         (-> (.fetch js/window hf-endpoint #js {:method "POST" :headers #js {:Authorization (str "Bearer " hf-token)
                                                                             :Content-Type  "application/json"}
                                                :body (js/JSON.stringify #js [text])})
             (.then #(.json %)) ; Get JSON from the Response.body ReadableStream
             (.then #(let [sentence-embed %
                           _  (println sentence-embed)
                           se-encoded (.map (aget sentence-embed "0") (comp (fn [s] (.toString s)) helpers/to64x61 (fn [n]
                                                                                                                     (+ n 1.0))))
                           prompt-h (text->p-hash selected-prompt)
                           response-h (text->p-hash-salted text salt)
                           response (get-local-item (str "response/" response-h))
                           prompt    (get-local-item (str "prompt/" prompt-h))
                           updated-prompt (-> prompt
                                              (assoc   :response-h response-h)
                                              (assoc :content selected-prompt))
                           updated-response (assoc response  :content text)
                           ;; updated-response (assoc response :disclosed true)
                           ]
                       (println prompt-h response-h se-encoded)
                       (submit-response! #js {:args #js [prompt-h
                                                         response-h
                                                         se-encoded
                                                         ]})
                       (set-local-item! (str "prompt/" prompt-h)  updated-prompt )
                       (set-local-item! (str "response/" response-h)  updated-response)))
             (.catch (fn
                       []
                       (set-hugging-error (str"Retrying sentence embedding service " @retries))
                       (vswap! retries inc)
                       ;; (if (= @retries 7)
                       ;;   (do
                       ;;    (set-hugging-error (str"sentence embedding service temporarily down, try again in a few minutes "))
                       ;;    (vreset! retries 0))
                       ;;   (do
                           
                       ;;     (js/setTimeout get-embed-and-transact 20000)))
                       ))
             )))
      (str "Submit response to prompt" )]
     [:f>  make-rv-view selected-prompt text]
     [:f>  matches-for-response-view selected-prompt text]
     ]))

(defn prompts-view []
  (let [contract-js (use-rv)

        contract (some-> contract-js
                         (aget "contract"))
        starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )
        call-get-prompt (useStarknetCall #js {:contract contract :method
                                                   "get_all_prompts"
                                              :args #js []})

        [selected-prompt set-selected-prompt] (react/useState "")        
        [prompt-js error loading]
        (mapv #(some->  call-get-prompt
                       (aget %1))
              ["data" "error" "loading"])
        %prompts (some->>
                  prompt-js
                  js->clj
                  
                  )
        ;; response-to-display (if (zero? response)
        ;;                       response
        ;;                       (->> response
        ;;                        (map (comp decodeShortString toHex) )
        ;;                        (apply str)))

        prompts
        (if (zero? (->> %prompts first))
          nil
         (->>
          %prompts
          first
          (reduce (fn [acc el]
                    ;; for some reason this is the only reliable equality for a bignumber equalling zero?
                    (if (= (.toString el) "0")
                      (conj acc  {:content ""
                                  :encoded []
                                  })
                      (let [updated-el (-> (peek acc)
                                           (update :content #(str % (bigint->string el)))
                                           (update :encoded #(conj % el)))

                                   
                            ]
                               
                        (conj (pop acc) updated-el)))
                    )
                  [])
          ))]

    (if error
      [:b error]
      (when (seq prompts)

        (when (and (= (count prompts) 1) (empty? selected-prompt))
          (set-selected-prompt (->> prompts first :content)))
        [:div
         [:select {:onChange (fn [e]
                               (set-selected-prompt e.target.value)
                               )}
          (map-indexed 
           (fn [idx {:keys [content encoded]}]
             [:option {:value content
                       :key (encoded-string->p-hash encoded)}
              content])
           prompts)]
         (println selected-prompt)
         [:f> response-view selected-prompt]
         ])
      )
    ))

(defn greeter []
  (let [starknet-js (useStarknet)
        account (some-> starknet-js
                        (aget "account")
                        )]
    (when account
      [:h4  (str "gm " (->> account
                            (take 5)
                            (apply str)))])))

(defn ^:export test-connectors []
  )

(def ^:export jhnn-provider (Provider. #js {:baseUrl "http://127.0.0.1:5050" }))

(defn simple-example []
  (let [injected-connectors (getInstalledInjectedConnectors)
        ]

    (if-not (seq (array-seq injected-connectors))
      (do
        (js/setTimeout init 1000))
      (do
        ;; (set! js/window.starknet_braavos.provider jhnn-provider)
        )
      )
    
   [(r/adapt-react-class StarknetProvider)
    {:connectors injected-connectors
     :defaultProvider jhnn-provider
     }
    [:f> greeter]
    [:f> connect]
    ;; [:f> greeter]
    [:f> prompts-view]    
    [:f> prompt-contract]


    ;; [clock]
    ;; [color-input]
    ]))

(defn  init []
  (rdom/render [simple-example] (js/document.getElementById "app")))





