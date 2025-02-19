# ml-ci-pipeline
Test setup tp practice automatic LLM fetching from huggingface. Uses docker-compose to run Jenkins, Minio and Nexus.
1)Modify model-config.yaml to specify the model to be fetched (name, repositry, size)
2)Run the pipeline
3)Check if the model has been fetched and the docker image is present in Nexus
